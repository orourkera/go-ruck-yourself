import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_bloc.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_event.dart';
import 'package:rucking_app/features/clubs/presentation/bloc/clubs_state.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';

/// Screen for creating a new club
class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({Key? key}) : super(key: key);

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxMembersController = TextEditingController();
  
  bool _isPublic = true;
  bool _isLoading = false;
  
  late ClubsBloc _clubsBloc;

  @override
  void initState() {
    super.initState();
    _clubsBloc = getIt<ClubsBloc>();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  void _createClub() {
    if (_formKey.currentState!.validate()) {
      final maxMembers = _maxMembersController.text.isEmpty 
          ? null 
          : int.tryParse(_maxMembersController.text);
      
      _clubsBloc.add(CreateClub(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        isPublic: _isPublic,
        maxMembers: maxMembers,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _clubsBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Create Club',
            style: AppTextStyles.titleLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark,
            ),
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
                    style: AppTextStyles.bodyLarge.copyWith(
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
                  
                  // Description
                  Text(
                    'Description (Optional)',
                    style: AppTextStyles.bodyLarge.copyWith(
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
                      if (value != null && value.length > 500) {
                        return 'Description must be less than 500 characters';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Privacy Setting
                  Text(
                    'Privacy',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          title: Text('Public Club'),
                          subtitle: Text('Anyone can find and join this club'),
                          value: true,
                          groupValue: _isPublic,
                          onChanged: (value) => setState(() => _isPublic = value!),
                          activeColor: AppColors.primary,
                        ),
                        Divider(height: 1, color: Colors.grey[300]),
                        RadioListTile<bool>(
                          title: Text('Private Club'),
                          subtitle: Text('Only invited members can join'),
                          value: false,
                          groupValue: _isPublic,
                          onChanged: (value) => setState(() => _isPublic = value!),
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Max Members
                  Text(
                    'Member Limit (Optional)',
                    style: AppTextStyles.bodyLarge.copyWith(
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
                  
                  // Create Button
                  CustomButton(
                    text: 'Create Club',
                    onPressed: _isLoading ? null : _createClub,
                    isLoading: _isLoading,
                    color: AppColors.primary,
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
                          '• Private clubs require manual approval of new members\n'
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
