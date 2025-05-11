import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_detail_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_card.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  
  @override
  void initState() {
    super.initState();
    _loadSessions();
  }
  
  Future<void> _loadSessions() async {
    // Get the session history bloc and request sessions
    final historyBloc = context.read<SessionHistoryBloc>();
    historyBloc.add(const LoadSessionHistory());
  }
  
  @override
  Widget build(BuildContext context) {
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
      ),
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: _loadSessions,
        child: BlocBuilder<SessionHistoryBloc, SessionHistoryState>(
          builder: (context, state) {
            if (state is SessionHistoryLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is SessionHistoryLoaded) {
              final sessions = state.sessions;
              
              if (sessions.isEmpty) {
                return _buildEmptyState();
              }
              
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return SessionCard(
                    session: session,
                    preferMetric: preferMetric,
                    onTap: () => _navigateToSessionDetail(session),
                  );
                },
              );
            } else if (state is SessionHistoryError) {
              return _buildErrorState(state.message);
            } else {
              return const Center(
                child: Text('No session data available. Pull down to refresh.'),
              );
            }
          },
        ),
      ),
    );
  }
  
  void _navigateToSessionDetail(RuckSession session) {
    AppLogger.info('Navigating to session detail for session ${session.id}');    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SessionDetailScreen(session: session),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hiking,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No rucks yet!!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to the screen where users create a new session
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CreateSessionScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Start New Ruck'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildErrorState(String message) {
    // Translate the error message to a user-friendly one
    final userFriendlyMessage = ErrorHandler.getUserFriendlyMessage(
      message, 
      'Session History'
    );
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            const Text(
              'Could Not Load Sessions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              userFriendlyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSessions,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}