# MITHAQ — Security and Privacy Baseline (Draft 0.1)

## 1. Default principles

- Collect the minimum data necessary for a defined product function.
- Explain purpose, access, retention, and deletion before collecting personal data.
- Keep production secrets and credentials out of source control, screenshots, issues, and logs.
- Restrict access by role and case; privileged access must be logged.
- Use encryption in transit and appropriate encryption at rest through vetted infrastructure.
- Separate development, test, and production data and credentials.
- Use synthetic data during development.

## 2. Identity and onboarding

Driver eligibility and identity checks may be required, but the process and lawful basis must be confirmed locally. Prefer a qualified verification provider or a controlled manual process over building biometric recognition.

Face verification is not a default requirement for this prototype. Before any biometric processing, assess necessity, proportionality, legal basis, accuracy, bias, fallback access, security, retention, and deletion. Do not store face templates or embeddings in the initial system.

Identity documents, if later required, must be stored in restricted encrypted object storage with short, justified retention and access audit. They must never be committed to Git.

## 3. Location privacy

- Request location permission only when needed and explain why.
- Do not track drivers continuously when they are offline.
- Limit precise location access to the passenger/driver pair for an active ride and authorized operations staff.
- Set explicit retention periods; delete or aggregate old location traces.
- Never expose a driver's or passenger's live location through public endpoints or guessable identifiers.

## 4. Application security

- Enforce authorization on every server endpoint and realtime subscription.
- Validate all input server-side.
- Apply rate limits to login, OTP, ride creation, offer acceptance, and safety reporting.
- Use secure session handling and account recovery.
- Protect against IDOR, replay, enumeration, injection, CSRF (where applicable), and abuse of public endpoints.
- Use idempotency keys for operations that may be retried.
- Keep dependencies updated and review licenses and known vulnerabilities.
- Backups must be encrypted and restoration tested.

## 5. Safety incident handling

Define an operational process before enabling an emergency feature: who receives alerts, at what hours, how quickly they respond, and what happens if the service is unavailable. Do not display an emergency button that implies monitored response when no staffed response exists. Provide clear local emergency guidance only after validating contact details and escalation procedures.

## 6. Minors and delegated rides

- Do not enable independent minor accounts in the first MVP.
- Any guardian-assisted or third-party booking flow requires explicit consent, clear identification of the actual passenger, and safeguarding/legal review.
- Do not assume the account holder is the person boarding.
- Record only the minimum information required to coordinate a delegated ride.

## 7. Development checklist

- [ ] No secrets committed.
- [ ] Authorization tests cover every role and resource.
- [ ] No real personal or location data in test fixtures.
- [ ] Sensitive logs are redacted.
- [ ] Retention and deletion behavior is tested.
- [ ] Security review completed before any external pilot.
- [ ] Incident response and support coverage documented.
