'use client';

const STEPS = [
  'Load room',
  'Invite friends',
  'Plan together',
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
            {step === 'Plan together' && onPlan ? (
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
        Core flow: invite → plan with friends → accept AI → drag or clear furniture already in
        the room. Advanced tools (timeline, disagreement, draw) live in the sidebar. Keys: click
        select · <kbd>Delete</kbd> twice to remove · <kbd>Ctrl</kbd>+<kbd>Z</kbd> undo ·{' '}
        <kbd>Esc</kbd> deselect.
      </p>
    </div>
  );
}
