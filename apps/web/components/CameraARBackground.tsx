'use client';

import { useEffect, useRef, useState } from 'react';

type Props = {
  /** When true, start/stop the rear (or default) camera as a full-bleed backdrop. */
  active: boolean;
};

/**
 * getUserMedia rear-camera backdrop for Camera AR overlays (no WebXR required).
 * Alignment is approximate (no 6DoF) — Map twin is the exact digital room model.
 */
export function CameraARBackground({ active }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!active) {
      setReady(false);
      setError(null);
      return;
    }
    let stream: MediaStream | null = null;
    let cancelled = false;

    const start = async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) {
          setError('Camera API unavailable in this browser');
          return;
        }
        stream = await navigator.mediaDevices.getUserMedia({
          audio: false,
          video: {
            facingMode: { ideal: 'environment' },
            width: { ideal: 1280 },
            height: { ideal: 720 }
          }
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        const video = videoRef.current;
        if (video) {
          video.srcObject = stream;
          await video.play();
          setReady(true);
          setError(null);
        }
      } catch (err) {
        const msg =
          err instanceof Error ? err.message : 'Could not open camera';
        setError(msg);
        setReady(false);
      }
    };

    void start();

    return () => {
      cancelled = true;
      setReady(false);
      if (stream) stream.getTracks().forEach((t) => t.stop());
      const video = videoRef.current;
      if (video) video.srcObject = null;
    };
  }, [active]);

  if (!active) return null;

  return (
    <div className="camera-ar-bg" aria-hidden>
      <video
        ref={videoRef}
        className={`camera-ar-video ${ready ? 'is-ready' : ''}`}
        playsInline
        muted
        autoPlay
      />
      {error ? (
        <div className="camera-ar-fallback">
          <p>Camera unavailable — allow camera access, or switch to Map twin.</p>
          <p className="camera-ar-fallback-detail">{error}</p>
        </div>
      ) : null}
    </div>
  );
}
