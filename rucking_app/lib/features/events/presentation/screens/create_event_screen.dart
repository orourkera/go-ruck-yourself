import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/location_search_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/shared/utils/image_picker_utils.dart';

class CreateEventScreen extends StatefulWidget {
  final String? eventId; // For editing existing events
  
  const CreateEventScreen({
    Key? key,
    this.eventId,
  }) : super(key: key);

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _minParticipantsController = TextEditingController();
  final _ruckWeightController = TextEditingController();
  
  // Focus nodes for keyboard navigation
  final _titleFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  final _locationFocusNode = FocusNode();
  final _minParticipantsFocusNode = FocusNode();
  final _maxParticipantsFocusNode = FocusNode();
  final _ruckWeightFocusNode = FocusNode();
  
  bool _isLoading = false;
  File? _bannerImage;
  DateTime? _selectedDateTime;
  int _duration = 60; // minutes
  int _difficultyLevel = 1;
  bool _isClubEvent = false;
  bool _approvalRequired = false;
  String? _selectedClubId;
  
  late EventsBloc _eventsBloc;
  late ClubsBloc _clubsBloc;
  final _locationSearchService = getIt<LocationSearchService>();
  LocationSearchResult? _selectedLocationResult;
  List<LocationSearchResult> _locationSuggestions = [];
  bool _showLocationSuggestions = false;
  
  List<Club> _userClubs = [];

  @override
  void initState() {
    super.initState();
    _eventsBloc = getIt<EventsBloc>();
    _clubsBloc = getIt<ClubsBloc>();
    
    // Load user's clubs for club event option
    _loadUserClubs();
    
    if (widget.eventId != null) {
      // Load event details for editing
      _eventsBloc.add(LoadEventDetails(widget.eventId!));
    }
  }

  void _loadUserClubs() {
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      // Load clubs where user is admin or member
      _clubsBloc.add(LoadClubs(membershipFilter: 'admin'));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    _minParticipantsController.dispose();
    _ruckWeightController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _locationFocusNode.dispose();
    _minParticipantsFocusNode.dispose();
    _maxParticipantsFocusNode.dispose();
    _ruckWeightFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.eventId != null;
    
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _eventsBloc),
        BlocProvider.value(value: _clubsBloc),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEditing ? 'Edit Event' : 'Create Event',
            style: AppTextStyles.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: _getLadyModeColor(context),
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: MultiBlocListener(
          listeners: [
            BlocListener<EventsBloc, EventsState>(
              listener: (context, state) {
                if (state is EventActionSuccess) {
                  Navigator.of(context).pop();
                  StyledSnackBar.showSuccess(
                    context: context,
                    message: state.message,
                  );
                } else if (state is EventActionError) {
                  StyledSnackBar.showError(
                    context: context,
                    message: state.message,
                  );
                }
              },
            ),
            BlocListener<ClubsBloc, ClubsState>(
              listener: (context, state) {
                if (state is ClubsLoaded) {
                  setState(() {
                    _userClubs = state.clubs.where((club) => club.userRole == 'admin').toList();
                    
                    // If user is admin of any clubs, default to true and select first club
                    if (_userClubs.isNotEmpty && widget.eventId == null) {
                      _isClubEvent = true;
                      _selectedClubId = _userClubs.first.id;
                    }
                  });
                }
              },
            ),
          ],
          child: BlocBuilder<EventsBloc, EventsState>(
            builder: (context, state) {
              if (state is EventDetailsLoaded && isEditing) {
                _populateFormWithEventData(state.eventDetails.event);
              }
              
              return _buildForm(isDarkMode);
            },
          ),
        ),
      ),
    );
  }

  Color _getLadyModeColor(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    return authState is Authenticated && authState.user.gender == 'female'
        ? AppColors.ladyPrimary
        : AppColors.primary;
  }

  Widget _buildForm(bool isDarkMode) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner image section
            _buildBannerImageSection(isDarkMode),
            
            const SizedBox(height: 24),
            
            // Basic info section
            _buildBasicInfoSection(isDarkMode),
            
            const SizedBox(height: 24),
            
            // Date and time section
            _buildDateTimeSection(isDarkMode),
            
            const SizedBox(height: 24),
            
            // Location section
            _buildLocationSection(isDarkMode),
            
            const SizedBox(height: 24),
            
            // Event settings section
            _buildEventSettingsSection(isDarkMode),
            
            const SizedBox(height: 24),
            
            // Club event section
            if (_userClubs.isNotEmpty) ...[
              _buildClubEventSection(isDarkMode),
              const SizedBox(height: 24),
            ],
            
            // Create/Update button
            _buildSubmitButton(isDarkMode),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerImageSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Banner',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withOpacity(0.3),
            ),
          ),
          child: _bannerImage != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 3.0,
                        child: Image.file(
                          _bannerImage!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _removeBannerImage,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: _selectBannerImage,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 40,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add Event Banner',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBasicInfoSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Information',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        TextFormField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _descriptionFocusNode.requestFocus(),
          decoration: InputDecoration(
            labelText: 'Event Title *',
            hintText: 'Enter event title',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter an event title';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _descriptionController,
          focusNode: _descriptionFocusNode,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _locationFocusNode.requestFocus(),
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: 'Describe your event...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildDateTimeSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date & Time',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        // Date and time picker
        InkWell(
          onTap: _selectDateTime,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey.withOpacity(0.3),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDateTime != null
                        ? DateFormat('MMM d, y \'at\' h:mm a').format(_selectedDateTime!)
                        : 'Select date and time *',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _selectedDateTime != null
                          ? (isDarkMode ? Colors.white : AppColors.textDark)
                          : Colors.grey[600],
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meeting Point',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        TextFormField(
          controller: _locationController,
          focusNode: _locationFocusNode,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _minParticipantsFocusNode.requestFocus(),
          decoration: InputDecoration(
            labelText: 'Meeting Point',
            hintText: 'Search for a meeting point, business, or address...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: _searchLocation,
        ),
        
        if (_showLocationSuggestions && _locationSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _locationSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _locationSuggestions[index];
                return ListTile(
                  title: Text(suggestion.displayName),
                  subtitle: Text(suggestion.address),
                  onTap: () => _selectLocationSuggestion(suggestion),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEventSettingsSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Settings',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        // Difficulty level
        Row(
          children: [
            Expanded(
              child: Text(
                'Difficulty Level: $_difficultyLevel',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDarkMode ? Colors.white : AppColors.textDark,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: _difficultyLevel.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (value) {
                  setState(() {
                    _difficultyLevel = value.round();
                  });
                },
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Participant limits
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minParticipantsController,
                focusNode: _minParticipantsFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _maxParticipantsFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'Min Participants',
                  hintText: 'e.g. 1',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _maxParticipantsController,
                focusNode: _maxParticipantsFocusNode,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _ruckWeightFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'Max Participants',
                  hintText: 'e.g. 20',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Recommended ruck weight
        TextFormField(
          controller: _ruckWeightController,
          focusNode: _ruckWeightFocusNode,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Recommended Ruck Weight (kg)',
            hintText: 'e.g. 10',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          keyboardType: TextInputType.number,
        ),
        
        const SizedBox(height: 16),
        
        // Duration
        Row(
          children: [
            Expanded(
              child: Text(
                'Approximate Duration: $_duration minutes',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isDarkMode ? Colors.white : AppColors.textDark,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: _duration.toDouble(),
                min: 15,
                max: 240,
                divisions: 15,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (value) {
                  setState(() {
                    _duration = value.round();
                  });
                },
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Approval required toggle
        SwitchListTile(
          title: Text(
            'Require Approval to Join',
            style: AppTextStyles.bodyLarge.copyWith(
              color: isDarkMode ? Colors.white : AppColors.textDark,
            ),
          ),
          subtitle: Text(
            'Review participants before they can join',
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.grey[600],
            ),
          ),
          value: _approvalRequired,
          onChanged: (value) {
            setState(() {
              _approvalRequired = value;
            });
          },
          activeColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildClubEventSection(bool isDarkMode) {
    if (_userClubs.isEmpty) {
      return const SizedBox.shrink(); // Don't show section if user has no admin clubs
    }
    
    final primaryColor = _getLadyModeColor(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Club Event',
          style: AppTextStyles.titleMedium.copyWith(
            color: isDarkMode ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        Container(
          decoration: BoxDecoration(
            color: _isClubEvent ? primaryColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isClubEvent ? primaryColor : Colors.grey.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: SwitchListTile(
            title: Text(
              _getClubEventTitle(),
              style: AppTextStyles.bodyLarge.copyWith(
                color: isDarkMode ? Colors.white : AppColors.textDark,
                fontWeight: _isClubEvent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              _isClubEvent 
                  ? 'Event will appear in club calendar and member feeds'
                  : 'Event will be personal only',
              style: AppTextStyles.bodySmall.copyWith(
                color: _isClubEvent ? primaryColor : Colors.grey[600],
              ),
            ),
            value: _isClubEvent,
            onChanged: (value) {
              setState(() {
                _isClubEvent = value;
                if (!value) {
                  _selectedClubId = null;
                } else if (_selectedClubId == null && _userClubs.isNotEmpty) {
                  _selectedClubId = _userClubs.first.id;
                }
              });
            },
            activeColor: primaryColor,
          ),
        ),
        
        if (_isClubEvent && _userClubs.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Select Club',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            value: _selectedClubId,
            items: _userClubs.map((club) {
              return DropdownMenuItem(
                value: club.id,
                child: Text(club.name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedClubId = value;
              });
            },
            validator: _isClubEvent ? (value) {
              if (value == null) {
                return 'Please select a club';
              }
              return null;
            } : null,
          ),
        ],
      ],
    );
  }
  
  String _getClubEventTitle() {
    if (!_isClubEvent || _selectedClubId == null || _userClubs.isEmpty) {
      return 'Host as Club Event';
    }
    
    try {
      final selectedClub = _userClubs.firstWhere((club) => club.id == _selectedClubId);
      return 'This is a ${selectedClub.name} Event';
    } catch (e) {
      return 'Host as Club Event';
    }
  }

  Widget _buildSubmitButton(bool isDarkMode) {
    final isEditing = widget.eventId != null;
    
    return SizedBox(
      width: double.infinity,
      child: CustomButton(
        text: isEditing ? 'Update Event' : 'Create Event',
        onPressed: _isLoading ? null : _submitForm,
        isLoading: _isLoading,
        color: Theme.of(context).primaryColor,
        textColor: Colors.white,
      ),
    );
  }

  Future<void> _selectBannerImage() async {
    final selectedFile = await ImagePickerUtils.pickEventBannerImage(context);
    if (selectedFile != null) {
      setState(() {
        _bannerImage = selectedFile;
      });
    }
  }

  void _removeBannerImage() {
    setState(() {
      _bannerImage = null;
    });
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          _selectedDateTime ?? DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      
      if (time != null) {
        setState(() {
          _selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _locationSuggestions = [];
        _showLocationSuggestions = false;
      });
      return;
    }

    try {
      final results = await _locationSearchService.searchWithDebounce(
        query,
        const Duration(milliseconds: 500),
      );
      
      setState(() {
        _locationSuggestions = results;
        _showLocationSuggestions = results.isNotEmpty;
      });
    } catch (e) {
      // Handle search error silently
      setState(() {
        _locationSuggestions = [];
        _showLocationSuggestions = false;
      });
    }
  }

  void _selectLocationSuggestion(LocationSearchResult suggestion) {
    setState(() {
      _locationController.text = suggestion.displayName;
      _selectedLocationResult = suggestion;
      _showLocationSuggestions = false;
      _locationSuggestions = [];
    });
  }

  void _populateFormWithEventData(dynamic event) {
    // This would populate the form fields with existing event data for editing
    // Implementation depends on the Event model structure
    _titleController.text = event.title ?? '';
    _descriptionController.text = event.description ?? '';
    _locationController.text = event.locationName ?? '';
    _selectedDateTime = event.scheduledStartTime;
    _duration = event.durationMinutes ?? 60;
    // ... populate other fields
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_selectedDateTime == null) {
      StyledSnackBar.showError(
        context: context,
        message: 'Please select a date and time',
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    final eventData = {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'scheduled_start_time': _selectedDateTime!,
      'location_name': _locationController.text.trim(),
      'location_latitude': _selectedLocationResult?.latitude,
      'location_longitude': _selectedLocationResult?.longitude,
      'difficulty_level': _difficultyLevel,
      'min_participants': _minParticipantsController.text.isNotEmpty 
          ? int.tryParse(_minParticipantsController.text) 
          : null,
      'max_participants': _maxParticipantsController.text.isNotEmpty 
          ? int.tryParse(_maxParticipantsController.text) 
          : null,
      'ruck_weight_kg': _ruckWeightController.text.isNotEmpty 
          ? double.tryParse(_ruckWeightController.text) 
          : null,
      'duration_minutes': _duration,
      'approval_required': _approvalRequired,
      'hosting_club_id': _isClubEvent ? _selectedClubId : null,
    };
    
    if (widget.eventId != null) {
      _eventsBloc.add(UpdateEvent(
        eventId: widget.eventId!,
        title: eventData['title'] as String,
        description: eventData['description'] as String?,
        scheduledStartTime: eventData['scheduled_start_time'] as DateTime,
        locationName: eventData['location_name'] as String?,
        latitude: eventData['location_latitude'] as double?,
        longitude: eventData['location_longitude'] as double?,
        maxParticipants: eventData['max_participants'] as int?,
        minParticipants: eventData['min_participants'] as int?,
        approvalRequired: eventData['approval_required'] as bool,
        difficultyLevel: eventData['difficulty_level'] as int?,
        ruckWeightKg: eventData['ruck_weight_kg'] as double?,
        durationMinutes: eventData['duration_minutes'] as int,
        bannerImageFile: _bannerImage, 
      ));
    } else {
      _eventsBloc.add(CreateEvent(
        title: eventData['title'] as String,
        description: eventData['description'] as String?,
        clubId: eventData['hosting_club_id'] as String?,
        scheduledStartTime: eventData['scheduled_start_time'] as DateTime,
        locationName: eventData['location_name'] as String?,
        latitude: eventData['location_latitude'] as double?,
        longitude: eventData['location_longitude'] as double?,
        maxParticipants: eventData['max_participants'] as int?,
        minParticipants: eventData['min_participants'] as int?,
        approvalRequired: eventData['approval_required'] as bool,
        difficultyLevel: eventData['difficulty_level'] as int?,
        ruckWeightKg: eventData['ruck_weight_kg'] as double?,
        durationMinutes: eventData['duration_minutes'] as int,
        bannerImageFile: _bannerImage, 
      ));
    }
  }
}
