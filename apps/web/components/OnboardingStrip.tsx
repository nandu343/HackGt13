'use client';

const STEPS = [
  'Enter Camera AR',
  'Invite friends',
  'Plan in AR',
  'Place & clear',
  'Shop'
];

export function OnboardingStrip({
  onPlan,
  onInvite
}: {
  onPlan?: () => void;
  onInvite?: () => void;
}) {
  return (
    <div className="onboarding-strip" role="note">
      <ol>
        {STEPS.map((step, i) => (
          <li key={step}>
            <span className="step-num">{i + 1}</span>
            {step === 'Plan in AR' && onPlan ? (
              <button type="button" className="linkish" onClick={onPlan}>
                {step}
              </button>
            ) : step === 'Invite friends' && onInvite ? (
              <button type="button" className="linkish" onClick={onInvite}>
                {step}
              </button>
            ) : (
              step
            )}
          </li>
        ))}
      </ol>
      <p className="onboarding-hint">
        Core flow: Camera AR over the real room → invite → plan with friends → accept AI → drag or
        clear furniture. AR sketch draws in free 3D space. Map twin is secondary. Keys: click select
        · <kbd>Delete</kbd> twice to remove · <kbd>Ctrl</kbd>+<kbd>Z</kbd> undo · <kbd>Esc</kbd>{' '}
        deselect.
      </p>
    </div>
  );
}
