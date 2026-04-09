# Security Policy

## Scope

Patra processes SQL strings and reads/writes .patra files. Attack surfaces:
- SQL injection via malformed queries — parser must reject, not execute
- Malformed .patra files — all page reads must validate bounds
- flock races — advisory locks are cooperative, not mandatory

## Reporting

Report vulnerabilities to robert.maccracken@gmail.com.
