import 'package:flutter/material.dart';

import 'data/supabase_app_repository.dart';
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
  final SupabaseAppRepository _repository = SupabaseAppRepository();  
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  AppUser? _currentUser;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Osteoporosis Pathways',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildAppTheme(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final user = _currentUser;
    if (user == null) {
      return AuthScreen(
        repository: _repository,
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
      onOpenQuestionnaireBuilder: (questionnaireId) async {
        await _pushAndRefresh(
          QuestionnaireBuilderScreen(
            repository: _repository,
            initialQuestionnaireId: questionnaireId,
          ),
        );
      },
      onOpenPathwayCase: (caseId) async {
        await _pushAndRefresh(
          PathwayFormScreen(
            repository: _repository,
            existingCaseId: caseId,
            onEvaluationReady: _openEvaluation,
          ),
        );
      },
      onCreatePathwayCase: () async {
        await _pushAndRefresh(
          PathwayFormScreen(
            repository: _repository,
            onEvaluationReady: _openEvaluation,
          ),
        );
      },
    );
  }

  Future<void> _pushAndRefresh(Widget screen) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    await navigator.push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      setState(() {});
    }
  }

  void _openEvaluation(
    ClinicalCase clinicalCase,
    PathwayEvaluation evaluation,
  ) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => RecommendationReviewScreen(
          clinicalCase: clinicalCase,
          evaluation: evaluation,
          repository: _repository,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _signOut() {
    setState(() => _currentUser = null);
  }
}
