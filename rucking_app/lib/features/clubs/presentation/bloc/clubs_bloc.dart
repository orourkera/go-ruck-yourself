import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/clubs/domain/repositories/clubs_repository.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';

class ClubsBloc extends Bloc<ClubsEvent, ClubsState> {
  final ClubsRepository _repository;

  ClubsBloc(this._repository) : super(ClubsInitial()) {
    on<LoadClubs>(_onLoadClubs);
    on<RefreshClubs>(_onRefreshClubs);
    on<CreateClub>(_onCreateClub);
    on<LoadClubDetails>(_onLoadClubDetails);
    on<UpdateClub>(_onUpdateClub);
    on<DeleteClub>(_onDeleteClub);
    on<RequestMembership>(_onRequestMembership);
    on<ManageMembership>(_onManageMembership);
    on<RemoveMembership>(_onRemoveMembership);
    on<LeaveClub>(_onLeaveClub);
  }

  Future<void> _onLoadClubs(LoadClubs event, Emitter<ClubsState> emit) async {
    emit(ClubsLoading());
    
    try {
      AppLogger.info('Loading clubs with search: ${event.search}, isPublic: ${event.isPublic}, membership: ${event.membershipFilter}');
      
      final clubs = await _repository.getClubs(
        search: event.search,
        isPublic: event.isPublic,
        membershipFilter: event.membershipFilter,
      );
      
      emit(ClubsLoaded(
        clubs: clubs,
        searchQuery: event.search,
        isPublicFilter: event.isPublic,
        membershipFilter: event.membershipFilter,
      ));
      
      AppLogger.info('Loaded ${clubs.length} clubs');
    } catch (e) {
      AppLogger.error('Error loading clubs: $e');
      emit(ClubsError('Failed to load clubs: ${e.toString()}'));
    }
  }

  Future<void> _onRefreshClubs(RefreshClubs event, Emitter<ClubsState> emit) async {
    // Get current filters if state is ClubsLoaded
    String? search;
    bool? isPublic;
    String? membershipFilter;
    
    if (state is ClubsLoaded) {
      final currentState = state as ClubsLoaded;
      search = currentState.searchQuery;
      isPublic = currentState.isPublicFilter;
      membershipFilter = currentState.membershipFilter;
    }
    
    add(LoadClubs(
      search: search,
      isPublic: isPublic,
      membershipFilter: membershipFilter,
    ));
  }

  Future<void> _onCreateClub(CreateClub event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Creating club...'));
    
    try {
      AppLogger.info('Creating club: ${event.name}');
      
      String? logoUrl;
      
      // Upload logo if provided
      if (event.logo != null) {
        emit(const ClubActionLoading('Uploading logo...'));
        try {
          // Use the AvatarService uploadClubLogo method (doesn't update user profile)
          final avatarService = getIt<AvatarService>();
          logoUrl = await avatarService.uploadClubLogo(event.logo!);
          AppLogger.info('Club logo uploaded successfully: $logoUrl');
        } catch (logoError) {
          AppLogger.error('Failed to upload club logo: $logoError');
          emit(ClubActionError('Failed to upload club logo: ${logoError.toString()}'));
          return;
        }
      }
      
      emit(const ClubActionLoading('Creating club...'));
      
      await _repository.createClub(
        name: event.name,
        description: event.description,
        isPublic: event.isPublic,
        maxMembers: event.maxMembers,
        logoUrl: logoUrl,
        latitude: event.latitude,
        longitude: event.longitude,
      );
      
      emit(const ClubActionSuccess('Club created successfully!'));
      
      // Refresh clubs list
      add(RefreshClubs());
      
      AppLogger.info('Club created successfully');
    } catch (e) {
      AppLogger.error('Error creating club: $e');
      emit(ClubActionError('Failed to create club: ${e.toString()}'));
    }
  }

  Future<void> _onLoadClubDetails(LoadClubDetails event, Emitter<ClubsState> emit) async {
    emit(ClubDetailsLoading(event.clubId));
    
    try {
      AppLogger.info('Loading club details for: ${event.clubId}');
      
      final clubDetails = await _repository.getClubDetails(event.clubId);
      
      emit(ClubDetailsLoaded(clubDetails));
      
      AppLogger.info('Loaded club details for: ${clubDetails.club.name}');
    } catch (e) {
      AppLogger.error('Error loading club details: $e');
      emit(ClubDetailsError('Failed to load club details: ${e.toString()}', event.clubId));
    }
  }

  Future<void> _onUpdateClub(UpdateClub event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Updating club...'));
    
    try {
      AppLogger.info('Updating club: ${event.clubId}');
      
      await _repository.updateClub(
        clubId: event.clubId,
        name: event.name,
        description: event.description,
        isPublic: event.isPublic,
        maxMembers: event.maxMembers,
        logo: event.logo,
        location: event.location,
        latitude: event.latitude,
        longitude: event.longitude,
      );
      
      emit(const ClubActionSuccess('Club updated successfully!'));
      
      // Refresh club details
      add(LoadClubDetails(event.clubId));
      
      AppLogger.info('Club updated successfully');
    } catch (e) {
      AppLogger.error('Error updating club: $e');
      emit(ClubActionError('Failed to update club: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteClub(DeleteClub event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Deleting club...'));
    
    try {
      AppLogger.info('Deleting club: ${event.clubId}');
      
      await _repository.deleteClub(event.clubId);
      
      emit(const ClubActionSuccess('Club deleted successfully!'));
      
      // Refresh clubs list
      add(RefreshClubs());
      
      AppLogger.info('Club deleted successfully');
    } catch (e) {
      AppLogger.error('Error deleting club: $e');
      emit(ClubActionError('Failed to delete club: ${e.toString()}'));
    }
  }

  Future<void> _onRequestMembership(RequestMembership event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Requesting membership...'));
    
    try {
      AppLogger.info('Requesting membership for club: ${event.clubId}');
      
      await _repository.requestMembership(event.clubId);
      
      emit(const ClubActionSuccess('Membership request sent!'));
      
      // Refresh club details to show pending status
      add(LoadClubDetails(event.clubId));
      
      AppLogger.info('Membership request sent successfully');
    } catch (e) {
      AppLogger.error('Error requesting membership: $e');
      emit(ClubActionError('Failed to request membership: ${e.toString()}'));
    }
  }

  Future<void> _onManageMembership(ManageMembership event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Managing membership...'));
    
    try {
      AppLogger.info('Managing membership for user ${event.userId} in club ${event.clubId}');
      
      await _repository.manageMembership(
        clubId: event.clubId,
        userId: event.userId,
        action: event.action,
        role: event.role,
      );
      
      String message = 'Membership updated successfully!';
      if (event.action == 'approve') {
        message = 'Membership approved!';
      } else if (event.action == 'reject') {
        message = 'Membership rejected!';
      }
      
      emit(ClubActionSuccess(message));
      
      // Refresh club details
      add(LoadClubDetails(event.clubId));
      
      AppLogger.info('Membership managed successfully');
    } catch (e) {
      AppLogger.error('Error managing membership: $e');
      emit(ClubActionError('Failed to manage membership: ${e.toString()}'));
    }
  }

  Future<void> _onRemoveMembership(RemoveMembership event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Removing member...'));
    
    try {
      AppLogger.info('Removing member ${event.userId} from club ${event.clubId}');
      
      await _repository.removeMembership(event.clubId, event.userId);
      
      emit(const ClubActionSuccess('Member removed successfully!'));
      
      // Refresh club details
      add(LoadClubDetails(event.clubId));
      
      AppLogger.info('Member removed successfully');
    } catch (e) {
      AppLogger.error('Error removing member: $e');
      emit(ClubActionError('Failed to remove member: ${e.toString()}'));
    }
  }

  Future<void> _onLeaveClub(LeaveClub event, Emitter<ClubsState> emit) async {
    emit(const ClubActionLoading('Leaving club...'));
    
    try {
      AppLogger.info('Leaving club: ${event.clubId}');
      
      await _repository.leaveClub(event.clubId);
      
      emit(const ClubActionSuccess('Left club successfully!'));
      
      // Refresh clubs list and club details
      add(RefreshClubs());
      
      AppLogger.info('Left club successfully');
    } catch (e) {
      AppLogger.error('Error leaving club: $e');
      emit(ClubActionError('Failed to leave club: ${e.toString()}'));
    }
  }
}
