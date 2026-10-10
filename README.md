# Secure Cross-Platform Patient Feedback and Clinical Decision Support System

CSI6224 Applied Project - Semester 2, 2026
Supervisor : Jumana Abu-Khalaf

## Project Overview

A web and Android application for osteoporosis assessment using Flutter and Supabase.

The system allows patients to complete questionnaires and clinicians to review patient information, enter investigations, and generate treatment recommendations using rule-based Pathways 1 and 2.

## Main Features

- Patient and clinician authentication
- Patient questionnaires and pathway eligibility checks
- Clinician questionnaire management
- Clinical investigations and rule-based decision support
- Clinician review and approval of recommendations
- Patient access to approved results

## Project Structure
- app/ – Flutter application (Web + Android)
- supabase/ – Database migrations, authentication, and Edge Functions

## Tech Stack
- Frontend: Flutter (Dart)
- Backend/Database: Supabase (PostgreSQL)
- Authentication: Supabase Auth
- Decision Support: Rule-based engine (Pathways 1 & 2)
