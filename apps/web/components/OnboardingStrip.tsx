'use client';

const STEPS = [
  'Load demo room',
  'Prompt AI',
  'Accept layout',
  'Voice · Draw · Drag',
  'Shop from catalog'
];

export function OnboardingStrip() {
  return (
    <div className="onboarding-strip" role="note">
      <ol>
        {STEPS.map((step, i) => (
          <li key={step}>
            <span className="step-num">{i + 1}</span>
            {step}
          </li>
        ))}
      </ol>
      <p className="onboarding-hint">
        Keys: click select · <kbd>Delete</kbd> remove · <kbd>Ctrl</kbd>+<kbd>Z</kbd> undo ·{' '}
        <kbd>Esc</kbd> deselect / exit draw · open a 2nd tab for voice + strokes
      </p>
    </div>
  );
}
