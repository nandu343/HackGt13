/**
 * Hackathon-practical WebRTC mesh voice over the scene WebSocket channel.
 *
 * Signaling: rtc_offer / rtc_answer / rtc_ice (targeted via fromUserId/toUserId).
 * Offerer rule: lexicographically smaller userId creates the offer.
 * STUN-only (no TURN) — works on same LAN / many home networks.
 */

import type { PresenceUser } from '@shared-spatial-ai/schema';
import type { SceneSocketMessage } from './ws';
import {
  sendRtcAnswer,
  sendRtcIce,
  sendRtcOffer,
  sendScenePresence,
  type PresencePayload
} from './ws';

const ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' }
];

export type VoiceState = {
  enabled: boolean;
  muted: boolean;
  speaking: boolean;
  error: string | null;
};

type PresenceFn = () => PresencePayload;

export class VoiceMesh {
  private localId: string;
  private getSocket: () => WebSocket | null;
  private getPresencePayload: PresenceFn;
  private pcs = new Map<string, RTCPeerConnection>();
  private remoteAudios = new Map<string, HTMLAudioElement>();
  private localStream: MediaStream | null = null;
  private audioCtx: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private vadTimer: number | null = null;
  private speaking = false;
  private muted = true;
  private enabled = false;
  private makingOffer = new Set<string>();
  private onState?: (s: VoiceState) => void;

  constructor(
    localId: string,
    getSocket: () => WebSocket | null,
    getPresencePayload: PresenceFn,
    onState?: (s: VoiceState) => void
  ) {
    this.localId = localId;
    this.getSocket = getSocket;
    this.getPresencePayload = getPresencePayload;
    this.onState = onState;
  }

  getState(): VoiceState {
    return {
      enabled: this.enabled,
      muted: this.muted,
      speaking: this.speaking,
      error: null
    };
  }

  private emit(extra?: Partial<VoiceState>) {
    this.onState?.({
      enabled: this.enabled,
      muted: this.muted,
      speaking: this.speaking,
      error: null,
      ...extra
    });
  }

  private pushPresence() {
    const sock = this.getSocket();
    if (!sock) return;
    sendScenePresence(sock, {
      ...this.getPresencePayload(),
      voiceEnabled: this.enabled,
      voiceSpeaking: this.speaking && !this.muted
    });
  }

  async enable(): Promise<void> {
    if (this.enabled) return;
    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        },
        video: false
      });
      this.muted = false;
      this.enabled = true;
      this.startVad();
      this.emit();
      this.pushPresence();
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Microphone permission denied';
      this.emit({ error: message, enabled: false });
      throw err;
    }
  }

  async disable(): Promise<void> {
    this.enabled = false;
    this.speaking = false;
    this.stopVad();
    for (const id of [...this.pcs.keys()]) {
      this.closePeer(id);
    }
    if (this.localStream) {
      for (const t of this.localStream.getTracks()) t.stop();
      this.localStream = null;
    }
    this.emit();
    this.pushPresence();
  }

  setMuted(muted: boolean): void {
    this.muted = muted;
    if (this.localStream) {
      for (const t of this.localStream.getAudioTracks()) {
        t.enabled = !muted;
      }
    }
    if (muted) this.speaking = false;
    this.emit();
    this.pushPresence();
  }

  toggleMute(): void {
    this.setMuted(!this.muted);
  }

  /** Sync mesh with presence list — call when presence updates. */
  syncPeers(presence: PresenceUser[]): void {
    if (!this.enabled || !this.localStream) return;
    const voicePeers = presence
      .filter((p) => p.userId !== this.localId && p.voiceEnabled)
      .map((p) => p.userId);

    for (const peerId of voicePeers) {
      if (!this.pcs.has(peerId) && this.localId < peerId) {
        void this.createOffer(peerId);
      }
    }
    for (const peerId of [...this.pcs.keys()]) {
      if (!voicePeers.includes(peerId)) {
        this.closePeer(peerId);
      }
    }
  }

  async handleSignal(msg: SceneSocketMessage): Promise<void> {
    if (!this.enabled) return;
    const from = msg.fromUserId;
    if (!from || from === this.localId) return;
    if (msg.toUserId && msg.toUserId !== this.localId) return;

    if (msg.type === 'rtc_offer' && msg.sdp) {
      const pc = this.ensurePc(from);
      if (this.makingOffer.has(from) || pc.signalingState !== 'stable') {
        // glare: ignore if we are also offering (we win by userId order)
        if (this.localId < from) return;
      }
      await pc.setRemoteDescription(msg.sdp);
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      const sock = this.getSocket();
      if (sock && pc.localDescription) {
        sendRtcAnswer(sock, this.localId, from, pc.localDescription);
      }
      return;
    }

    if (msg.type === 'rtc_answer' && msg.sdp) {
      const pc = this.pcs.get(from);
      if (!pc) return;
      await pc.setRemoteDescription(msg.sdp);
      return;
    }

    if (msg.type === 'rtc_ice' && msg.candidate) {
      const pc = this.pcs.get(from) ?? this.ensurePc(from);
      try {
        await pc.addIceCandidate(msg.candidate);
      } catch {
        // candidate may arrive before remote description
      }
    }
  }

  dispose(): void {
    void this.disable();
  }

  private ensurePc(peerId: string): RTCPeerConnection {
    let pc = this.pcs.get(peerId);
    if (pc) return pc;

    pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    this.pcs.set(peerId, pc);

    if (this.localStream) {
      for (const track of this.localStream.getTracks()) {
        pc.addTrack(track, this.localStream);
      }
    }

    pc.onicecandidate = (ev) => {
      const sock = this.getSocket();
      if (!sock) return;
      sendRtcIce(
        sock,
        this.localId,
        peerId,
        ev.candidate ? ev.candidate.toJSON() : null
      );
    };

    pc.ontrack = (ev) => {
      let audio = this.remoteAudios.get(peerId);
      if (!audio) {
        audio = document.createElement('audio');
        audio.autoplay = true;
        audio.setAttribute('playsinline', 'true');
        document.body.appendChild(audio);
        this.remoteAudios.set(peerId, audio);
      }
      audio.srcObject = ev.streams[0] ?? new MediaStream([ev.track]);
      void audio.play().catch(() => {
        // autoplay may need a user gesture (join voice is the gesture)
      });
    };

    pc.onconnectionstatechange = () => {
      if (
        pc!.connectionState === 'failed' ||
        pc!.connectionState === 'closed' ||
        pc!.connectionState === 'disconnected'
      ) {
        // keep entry; syncPeers / disable will clean up
      }
    };

    return pc;
  }

  private async createOffer(peerId: string): Promise<void> {
    if (this.makingOffer.has(peerId)) return;
    this.makingOffer.add(peerId);
    try {
      const pc = this.ensurePc(peerId);
      const offer = await pc.createOffer({ offerToReceiveAudio: true });
      await pc.setLocalDescription(offer);
      const sock = this.getSocket();
      if (sock && pc.localDescription) {
        sendRtcOffer(sock, this.localId, peerId, pc.localDescription);
      }
    } finally {
      this.makingOffer.delete(peerId);
    }
  }

  private closePeer(peerId: string): void {
    const pc = this.pcs.get(peerId);
    if (pc) {
      pc.close();
      this.pcs.delete(peerId);
    }
    const audio = this.remoteAudios.get(peerId);
    if (audio) {
      audio.srcObject = null;
      audio.remove();
      this.remoteAudios.delete(peerId);
    }
  }

  private startVad(): void {
    this.stopVad();
    if (!this.localStream) return;
    try {
      this.audioCtx = new AudioContext();
      const src = this.audioCtx.createMediaStreamSource(this.localStream);
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 512;
      src.connect(this.analyser);
      const data = new Uint8Array(this.analyser.frequencyBinCount);
      this.vadTimer = window.setInterval(() => {
        if (!this.analyser || this.muted) {
          if (this.speaking) {
            this.speaking = false;
            this.emit();
            this.pushPresence();
          }
          return;
        }
        this.analyser.getByteFrequencyData(data);
        let sum = 0;
        for (let i = 0; i < data.length; i++) sum += data[i];
        const avg = sum / data.length;
        const next = avg > 18;
        if (next !== this.speaking) {
          this.speaking = next;
          this.emit();
          this.pushPresence();
        }
      }, 200);
    } catch {
      // VAD optional
    }
  }

  private stopVad(): void {
    if (this.vadTimer != null) {
      window.clearInterval(this.vadTimer);
      this.vadTimer = null;
    }
    if (this.audioCtx) {
      void this.audioCtx.close();
      this.audioCtx = null;
    }
    this.analyser = null;
  }
}
