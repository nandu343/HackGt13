'use client';

import { useEffect, useState } from 'react';
import {
  buildInviteJoinUrl,
  createSceneInvite,
  fetchDefaultInvite
} from '../lib/api';
import { useSceneStore } from '../lib/sceneStore';

type Props = {
  open: boolean;
  onClose: () => void;
};

export function InviteModal({ open, onClose }: Props) {
  const { scene, actorId, displayName, setDisplayName, presence, pushToast, isBusy } =
    useSceneStore();
  const [link, setLink] = useState('');
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [nameDraft, setNameDraft] = useState(displayName);

  useEffect(() => {
    if (!open || !scene) return;
    setNameDraft(displayName);
    let cancelled = false;
    setLoading(true);
    void (async () => {
      try {
        const invite = await fetchDefaultInvite(scene.sceneId);
        if (cancelled) return;
        setLink(buildInviteJoinUrl(scene.sceneId, invite.token));
      } catch {
        if (!cancelled) {
          setLink(buildInviteJoinUrl(scene.sceneId));
          pushToast('Invite API unavailable — share scene link only', 'error');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [open, scene, displayName, pushToast]);

  if (!open || !scene) return null;

  const onCopy = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      pushToast('Invite link copied', 'success');
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      pushToast('Could not copy — select the link manually', 'error');
    }
  };

  const onFresh = async () => {
    setLoading(true);
    try {
      const invite = await createSceneInvite(scene.sceneId, {
        actorId,
        label: 'Friends invite'
      });
      setLink(buildInviteJoinUrl(scene.sceneId, invite.token));
      pushToast('New invite link ready', 'success');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Failed to create invite', 'error');
    } finally {
      setLoading(false);
    }
  };

  const onSaveName = () => {
    const next = nameDraft.trim() || displayName;
    setDisplayName(next);
    pushToast(`You'll appear as ${next}`, 'info');
  };

  return (
    <div
      className="intent-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="invite-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="intent-modal invite-modal">
        <header className="intent-header">
          <div>
            <p className="eyebrow">Share</p>
            <h2 id="invite-title">Invite link</h2>
            <p className="intent-sub">
              Anyone with the link can join this scene. Voice mesh may degrade with large groups.
            </p>
          </div>
          <button type="button" className="btn ghost compact" onClick={onClose}>
            Close
          </button>
        </header>

        <label className="field">
          <span>Your display name</span>
          <div className="invite-name-row">
            <input
              value={nameDraft}
              onChange={(e) => setNameDraft(e.target.value)}
              placeholder="e.g. Alex"
              maxLength={40}
              disabled={isBusy}
            />
            <button type="button" className="btn compact" onClick={onSaveName}>
              Save
            </button>
          </div>
        </label>

        <label className="field">
          <span>Invite link</span>
          <input
            readOnly
            value={loading ? 'Preparing link…' : link}
            onFocus={(e) => e.target.select()}
            aria-busy={loading}
          />
        </label>

        <div className="btn-row">
          <button
            type="button"
            className="btn primary"
            onClick={() => void onCopy()}
            disabled={!link || loading}
          >
            {copied ? 'Copied' : 'Copy link'}
          </button>
          <button
            type="button"
            className="btn ghost"
            onClick={() => void onFresh()}
            disabled={loading || isBusy}
          >
            New link
          </button>
        </div>

        <p className="intent-foot">
          {presence.length} online now · scene <code>{scene.sceneId}</code>
          {link.includes('invite=') ? ' · tokenized invite' : ''}
        </p>
      </div>
    </div>
  );
}
