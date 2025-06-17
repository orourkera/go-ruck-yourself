import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/avatar_service.dart';
import 'package:rucking_app/core/services/location_search_service.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/utils/image_picker_utils.dart';

/// Screen for creating a new club
class CreateClubScreen extends StatefulWidget {
  final ClubDetails? clubToEdit;
  
  const CreateClubScreen({Key? key, this.clubToEdit}) : super(key: key);

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxMembersController = TextEditingController();
  final _locationController = TextEditingController();
  
  bool _isLoading = false;
  File? _clubLogo;
  
  late ClubsBloc _clubsBloc;
  final _locationSearchService = getIt<LocationSearchService>();
  LocationSearchResult? _selectedLocationResult;
  List<LocationSearchResult> _locationSuggestions = [];
  bool _showLocationSuggestions = false;

  @override
  void initState() {
    super.initState();
    _clubsBloc = getIt<ClubsBloc>();
    
    // Pre-fill form if editing existing club
    if (widget.clubToEdit != null) {
      final club = widget.clubToEdit!.club;
      _nameController.text = club.name;
      _descriptionController.text = club.description ?? '';
      _maxMembersController.text = club.maxMembers?.toString() ?? '';
      
      // Set location if available
      if (club.latitude != null && club.longitude != null) {
        // Create a location result from the existing club data
        _selectedLocationResult = LocationSearchResult(
          displayName: club.location ?? 'Club Location',
          address: club.location ?? 'Club Location', // Use location field as address
          latitude: club.latitude!,
          longitude: club.longitude!,
        );
        _locationController.text = club.location ?? 'Club Location';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxMembersController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectLogo() async {
    final selectedFile = await ImagePickerUtils.pickImage(context, showCropModal: true);
    if (selectedFile != null) {
      setState(() {
        _clubLogo = selectedFile;
      });
    }
  }

  void _removeLogo() {
    setState(() {
      _clubLogo = null;
    });
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
      
      if (mounted) {
        setState(() {
          _locationSuggestions = results;
          _showLocationSuggestions = results.isNotEmpty;
        });
      }
    } catch (e) {
      // Handle search error silently
      if (mounted) {
        setState(() {
          _locationSuggestions = [];
          _showLocationSuggestions = false;
        });
      }
    }
  }

  void _selectLocation(LocationSearchResult location) {
    setState(() {
      _selectedLocationResult = location;
      _locationController.text = location.displayName;
      _showLocationSuggestions = false;
      _locationSuggestions = [];
    });
  }

  void _clearLocation() {
    setState(() {
      _selectedLocationResult = null;
      _locationController.clear();
      _showLocationSuggestions = false;
      _locationSuggestions = [];
    });
  }

  void _createClub() {
    if (_formKey.currentState!.validate()) {
      final maxMembers = _maxMembersController.text.isEmpty 
          ? null 
          : int.tryParse(_maxMembersController.text);
      
      if (widget.clubToEdit != null) {
        // Update existing club
        _clubsBloc.add(UpdateClub(
          clubId: widget.clubToEdit!.club.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          isPublic: true, // Keep existing setting for now
          maxMembers: maxMembers,
          logo: _clubLogo,
          location: _selectedLocationResult?.displayName,
          latitude: _selectedLocationResult?.latitude,
          longitude: _selectedLocationResult?.longitude,
        ));
      } else {
        // Create new club
        _clubsBloc.add(CreateClub(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          isPublic: true,
          maxMembers: maxMembers,
          logo: _clubLogo,
          location: _selectedLocationResult?.displayName,
          latitude: _selectedLocationResult?.latitude,
          longitude: _selectedLocationResult?.longitude,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _clubsBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.clubToEdit != null ? 'Edit Club' : 'Create Club',
            style: AppTextStyles.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: BlocListener<ClubsBloc, ClubsState>(
          listener: (context, state) {
            if (state is ClubActionLoading) {
              setState(() => _isLoading = true);
            } else {
              setState(() => _isLoading = false);
            }
            
            if (state is ClubActionSuccess) {
              // Club created successfully, navigate back
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.success,
                ),
              );
              Navigator.of(context).pop();
            } else if (state is ClubActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Club Name
                  Text(
                    'Club Name',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter club name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Club name is required';
                      }
                      if (value.trim().length < 3) {
                        return 'Club name must be at least 3 characters';
                      }
                      if (value.trim().length > 100) {
                        return 'Club name must be less than 100 characters';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Club Logo
                  Text(
                    'Club Logo (Optional)',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    width: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey[300]!,
                        width: 2,
                      ),
                      color: Colors.grey[50],
                    ),
                    child: _clubLogo != null
                        ? Stack(
                            children: [
                              // Logo preview - circular
                              ClipRRect(
                                borderRadius: BorderRadius.circular(60), // Half of 120 for perfect circle
                                child: Image.file(
                                  _clubLogo!,
                                  width: 116,
                                  height: 116,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Remove button
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: _removeLogo,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
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
                        : GestureDetector(
                            onTap: _selectLogo,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 40,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Add Logo',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Description
                  Text(
                    'Description *',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Describe your club, its purpose, and what members can expect...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Description is required';
                      }
                      if (value.trim().length < 20) {
                        return 'Description must be at least 20 characters';
                      }
                      if (value.length > 500) {
                        return 'Description must be less than 500 characters';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Location
                  Text(
                    'Location (Optional)',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    children: [
                      TextFormField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          hintText: 'Enter city, state, address, or landmark',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          suffixIcon: _selectedLocationResult != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearLocation,
                                )
                              : const Icon(Icons.search),
                        ),
                        onChanged: _searchLocation,
                      ),
                      
                      // Location suggestions dropdown
                      if (_showLocationSuggestions && _locationSuggestions.isNotEmpty)
                        Positioned(
                          top: 60,
                          left: 0,
                          right: 0,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _locationSuggestions.length,
                                itemBuilder: (context, index) {
                                  final suggestion = _locationSuggestions[index];
                                  return ListTile(
                                    leading: const Icon(Icons.location_on, size: 20),
                                    title: Text(
                                      suggestion.displayName,
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                    subtitle: suggestion.address != suggestion.displayName
                                        ? Text(
                                            suggestion.address,
                                            style: AppTextStyles.bodySmall.copyWith(
                                              color: Colors.grey[600],
                                            ),
                                          )
                                        : null,
                                    onTap: () => _selectLocation(suggestion),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Max Members
                  Text(
                    'Member Limit (Optional)',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _maxMembersController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Leave empty for unlimited members',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final number = int.tryParse(value);
                        if (number == null) {
                          return 'Please enter a valid number';
                        }
                        if (number < 2) {
                          return 'Must allow at least 2 members';
                        }
                        if (number > 1000) {
                          return 'Maximum limit is 1000 members';
                        }
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Create/Update Button
                  CustomButton(
                    text: widget.clubToEdit != null ? 'Update Club' : 'Create Club',
                    onPressed: _isLoading ? null : _createClub,
                    isLoading: _isLoading,
                    color: Theme.of(context).primaryColor,
                    width: double.infinity,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.info.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.info,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Club Guidelines',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• You will be the club admin and can manage members\n'
                          '• Club names must be unique and appropriate\n'
                          '• You can change these settings later in club management',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.info,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
