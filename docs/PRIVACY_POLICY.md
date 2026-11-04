# Privacy Policy

> This document describes [jrocha25/kube-exam-simulator](https://github.com/jrocha25/kube-exam-simulator), an unofficial fork of [sailor-sh/CK-X](https://github.com/sailor-sh/CK-X) that is not affiliated with Sailor.sh. It does not describe the upstream project.

**Effective Date:** [Insert Date]

## 1. Introduction
CK-X is an independent Kubernetes certification exam simulator. This Privacy Policy explains how we handle user data and ensure transparency regarding data collection and usage.

## 2. No Affiliation
CK-X is **not affiliated with, endorsed by, or associated with the Cloud Native Computing Foundation (CNCF), the Linux Foundation, or PSI.** Any references to Kubernetes, CKAD, CKA, or CKS are for descriptive purposes only, and all trademarks belong to their respective owners.

## 3. Data Collection
CK-X collects **no** data. It contains no telemetry, analytics, usage reporting, or crash reporting, and it sends nothing to us or to any third party.

Everything CK-X stores stays on the machine you run it on:
- Exam state, results, and answers live in the local Redis container that ships with the deployment.
- Your preferences and settings live in your browser's local storage.

Both are removed when you terminate the session or tear down the containers. We **do not** collect personal information, sell user data, or share it with third parties.

> Note: the web interface loads a few front-end assets (Bootstrap, xterm.js, Font Awesome, and a web font) from public CDNs, and the exam environments pull container images and Kubernetes tooling from their upstream registries. Those requests are made by your browser and by Docker to serve the application itself — they carry no CK-X usage data.

## 4. Use of Third-Party Tools
CK-X may utilize open-source components and third-party tools, which are subject to their respective licenses. Users are responsible for reviewing those licenses where applicable.

## 5. No Guarantees
CK-X is provided for educational purposes only. We do **not** guarantee:
- That the content reflects actual CKAD, CKA, or CKS exam questions.
- That using CK-X will result in passing any certification exam.

## 6. Question Content
All questions in CK-X are either **originally created** for educational purposes or **contributed by community contributors**. We do **not copy or reproduce** actual exam questions from any official sources.

## 7. Policy Changes
We may update this Privacy Policy from time to time. Continued use of CK-X after any changes implies acceptance of the updated terms.
