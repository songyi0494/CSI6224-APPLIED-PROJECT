import 'package:flutter/material.dart';

import 'data/mock_app_repository.dart';
import 'models/app_user.dart';
import 'models/clinical_case.dart';
import 'models/pathway_evaluation.dart';
import 'screens/auth_screen.dart';
import 'screens/clinician_dashboard_screen.dart';
import 'screens/pathway_form_screen.dart';
import 'screens/patient_home_screen.dart';
import 'screens/questionnaire_builder_screen.dart';
import 'screens/recommendation_review_screen.dart';
import 'theme/app_theme.dart';

class OsteoporosisPathwaysApp extends StatefulWidget {
  const OsteoporosisPathwaysApp({super.key});

  @override
  State<OsteoporosisPathwaysApp> createState() =>
      _OsteoporosisPathwaysAppState();
}

class _OsteoporosisPathwaysAppState extends State<OsteoporosisPathwaysApp> {
  final MockAppRepository _repository = MockAppRepository();
  AppUser? _currentUser;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSI6224 Pathways',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final user = _currentUser;
    if (user == null) {
      return AuthScreen(
        onSignedIn: (nextUser) => setState(() => _currentUser = nextUser),
      );
    }

    if (user.role == UserRole.patient) {
      return PatientHomeScreen(
        user: user,
        repository: _repository,
        onSignOut: _signOut,
      );
    }

    return ClinicianDashboardScreen(
      user: user,
      repository: _repository,
      onSignOut: _signOut,
      onOpenQuestionnaireBuilder: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuestionnaireBuilderScreen(repository: _repository),
          ),
        );
      },
      onOpenPathwayCase: (caseId) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PathwayFormScreen(
              repository: _repository,
              existingCaseId: caseId,
              onEvaluationReady: _openEvaluation,
            ),
          ),
        );
      },
      onCreatePathwayCase: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PathwayFormScreen(
              repository: _repository,
              onEvaluationReady: _openEvaluation,
            ),
          ),
        );
      },
    );
  }

  void _openEvaluation(
    ClinicalCase clinicalCase,
    PathwayEvaluation evaluation,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecommendationReviewScreen(
          clinicalCase: clinicalCase,
          evaluation: evaluation,
          repository: _repository,
        ),
      ),
    );
  }

  void _signOut() {
    setState(() => _currentUser = null);
  }
}
