import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/location_search_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_bloc.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_event.dart';
import 'package:rucking_app/features/events/presentation/bloc/events_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
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
      // This would need to be implemented in ClubsBloc
      // For now, we'll assume empty list
      setState(() {
        _userClubs = [];
      });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.eventId != null;
    
    return BlocProvider.value(
      value: _eventsBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEditing ? 'Edit Event' : 'Create Event',
            style: AppTextStyles.titleLarge.copyWith(
              color: isDarkMode ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: BlocConsumer<EventsBloc, EventsState>(
          listener: (context, state) {
            if (state is EventActionSuccess) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
            } else if (state is EventActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is EventDetailsLoaded && isEditing) {
              _populateFormWithEventData(state.eventDetails.event);
            }
            
            return _buildForm(isDarkMode);
          },
        ),
      ),
    );
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
                      child: Image.file(
                        _bannerImage!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
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
          decoration: InputDecoration(
            labelText: 'Event Title *',
            hintText: 'Enter event title',
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
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: 'Describe your event...',
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
          decoration: InputDecoration(
            labelText: 'Meeting Point',
            hintText: 'Search for a meeting point, business, or address...',
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
                decoration: InputDecoration(
                  labelText: 'Min Participants',
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
                decoration: InputDecoration(
                  labelText: 'Max Participants',
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
          decoration: InputDecoration(
            labelText: 'Recommended Ruck Weight (kg)',
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
        
        SwitchListTile(
          title: Text(
            'Host as Club Event',
            style: AppTextStyles.bodyLarge.copyWith(
              color: isDarkMode ? Colors.white : AppColors.textDark,
            ),
          ),
          subtitle: Text(
            'Event will be associated with one of your clubs',
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.grey[600],
            ),
          ),
          value: _isClubEvent,
          onChanged: (value) {
            setState(() {
              _isClubEvent = value;
              if (!value) {
                _selectedClubId = null;
              }
            });
          },
          activeColor: Theme.of(context).primaryColor,
        ),
        
        if (_isClubEvent) ...[
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date and time'),
          backgroundColor: Colors.red,
        ),
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
