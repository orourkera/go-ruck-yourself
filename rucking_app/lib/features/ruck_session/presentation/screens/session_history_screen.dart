import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/session_history_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/social/presentation/bloc/social_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/create_session_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/session_detail_screen.dart';
import 'package:rucking_app/features/ruck_session/presentation/widgets/session_card.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:rucking_app/features/premium/presentation/widgets/premium_tab_interceptor.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/widgets/skeleton/skeleton_widgets.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> with SingleTickerProviderStateMixin {
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSessions();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadSessions() async {
    // Get the session history bloc and request sessions
    final historyBloc = context.read<SessionHistoryBloc>();
    
    // Trigger fresh load
    historyBloc.add(const LoadSessionHistory());
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History & Stats'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(
              icon: Icon(Icons.history),
              text: 'History',
            ),
            Tab(
              icon: Icon(Icons.analytics),
              text: 'Stats',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          const PremiumTabInterceptor(
            tabIndex: 3,
            featureName: 'Statistics',
            child: StatisticsScreen(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHistoryTab() {
    // Get user preferences for metric/imperial
    final authState = context.read<AuthBloc>().state;
    final bool preferMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    return RefreshIndicator(
      key: _refreshKey,
      onRefresh: _loadSessions,
      child: BlocBuilder<SessionHistoryBloc, SessionHistoryState>(
        builder: (context, state) {
          AppLogger.info('[SESSION_HISTORY_SCREEN] Building UI with state: ${state.runtimeType}');
          
          if (state is SessionHistoryLoading) {
            AppLogger.info('[SESSION_HISTORY_SCREEN] Showing loading skeleton');
            return SingleChildScrollView(
              child: Column(
                children: List.generate(5, (index) => const SessionCardSkeleton()),
              ),
            );
          } else if (state is SessionHistoryLoaded) {
            final sessions = state.sessions;
            AppLogger.info('[SESSION_HISTORY_SCREEN] Loaded state with ${sessions.length} sessions');
            
            if (sessions.isEmpty) {
              AppLogger.info('[SESSION_HISTORY_SCREEN] No sessions found, showing empty state');
              return _buildEmptyState();
            }
            
            AppLogger.info('[SESSION_HISTORY_SCREEN] Building ListView with ${sessions.length} sessions');
            for (int i = 0; i < sessions.length; i++) {
              AppLogger.debug('[SESSION_HISTORY_SCREEN] Session $i: id=${sessions[i].id}, status=${sessions[i].status}');
            }
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length + (state.hasMoreData ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == sessions.length) {
                  // Load more button or loading indicator
                  if (state.isLoadingMore) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<SessionHistoryBloc>().add(
                              const LoadSessionHistory(loadMore: true),
                            );
                          },
                          child: const Text('Load More Sessions'),
                        ),
                      ),
                    );
                  }
                }
                
                final session = sessions[index];
                AppLogger.debug('[SESSION_HISTORY_SCREEN] Building SessionCard for session ${session.id}');
                return SessionCard(
                  session: session,
                  preferMetric: preferMetric,
                  onTap: () => _navigateToSessionDetail(session),
                );
              },
            );
          } else if (state is SessionHistoryError) {
            AppLogger.error('[SESSION_HISTORY_SCREEN] Error state: ${state.message}');
            return _buildErrorState(state.message);
          } else {
            AppLogger.warning('[SESSION_HISTORY_SCREEN] Unknown state: ${state.runtimeType}');
            return const Center(
              child: Text('No session data available. Pull down to refresh.'),
            );
          }
        },
      ),
    );
  }
  
  Future<void> _navigateToSessionDetail(RuckSession session) async {
    AppLogger.info('Navigating to session detail for session ${session.id}');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading session...'),
          ],
        ),
      ),
    );
    try {
      final repo = GetIt.instance<SessionRepository>();
      final fullSession = await repo.fetchSessionById(session.id!);
      Navigator.of(context).pop(); // Remove loading dialog
      if (fullSession != null) {
        Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => SessionDetailScreen(session: fullSession),
          ),
        ).then((refreshNeeded) {
          // If returned with true (session deleted), refresh the data
          if (refreshNeeded == true) {
            context.read<SessionHistoryBloc>().add(const LoadSessionHistory());
          }
        });
      } else {
        StyledSnackBar.showError(
          context: context,
          message: 'Failed to load session details',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();
      StyledSnackBar.showError(
        context: context,
        message: 'Error fetching session: $e',
        duration: const Duration(seconds: 2),
      );
    }
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
            Text(
              'No rucks yet!!',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w600,
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
            Text(
              'Could Not Load Sessions',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              userFriendlyMessage,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
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