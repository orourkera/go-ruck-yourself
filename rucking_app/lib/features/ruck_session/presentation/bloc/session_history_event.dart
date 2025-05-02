part of 'session_history_bloc.dart';

enum SessionFilter {
  all,
  thisWeek,
  thisMonth,
  lastMonth,
  custom,
}

abstract class SessionHistoryEvent extends Equatable {
  const SessionHistoryEvent();
  
  @override
  List<Object?> get props => [];
}

class LoadSessionHistory extends SessionHistoryEvent {
  final SessionFilter? filter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  
  const LoadSessionHistory({
    this.filter,
    this.customStartDate,
    this.customEndDate,
  });
  
  @override
  List<Object?> get props => [filter, customStartDate, customEndDate];
}

class FilterSessionHistory extends SessionHistoryEvent {
  final SessionFilter filter;
  
  const FilterSessionHistory(this.filter);
  
  @override
  List<Object?> get props => [filter];
}
