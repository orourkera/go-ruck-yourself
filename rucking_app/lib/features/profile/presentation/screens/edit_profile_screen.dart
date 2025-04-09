import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';

/// Screen for editing user profile
class EditProfileScreen extends StatefulWidget {
  final User user;

  const EditProfileScreen({
    Key? key,
    required this.user,
  }) : super(key: key);

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _weightController = TextEditingController(
      text: widget.user.weightKg?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: widget.user.heightCm?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  /// Saves the user profile changes
  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _saving = true;
      });

      double? weight = _weightController.text.isEmpty
          ? null
          : double.parse(_weightController.text);
          
      double? height = _heightController.text.isEmpty
          ? null
          : double.parse(_heightController.text);

      context.read<AuthBloc>().add(
        AuthProfileUpdateRequested(
          name: _nameController.text.trim(),
          weightKg: weight,
          heightCm: height,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            // Update successful, pop screen
            Navigator.pop(context);
          } else if (state is AuthError) {
            // Show error message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
              ),
            );
            setState(() {
              _saving = false;
            });
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile avatar
                Center(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      _getInitials(widget.user.name),
                      style: AppTextStyles.headline4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Name field
                CustomTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter your name',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Weight field
                CustomTextField(
                  controller: _weightController,
                  label: 'Weight (kg) - Optional',
                  hint: 'Enter your weight',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.monitor_weight_outlined,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (double.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                      if (double.parse(value) <= 0) {
                        return 'Weight must be greater than 0';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Height field
                CustomTextField(
                  controller: _heightController,
                  label: 'Height (cm) - Optional',
                  hint: 'Enter your height',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.height_outlined,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (double.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                      if (double.parse(value) <= 0) {
                        return 'Height must be greater than 0';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                
                // Helper text
                Text(
                  'Weight and height information help calculate calories burned during your rucking sessions more accurately.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textDarkSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Save button
                CustomButton(
                  text: 'Save Changes',
                  isLoading: _saving,
                  onPressed: _saveProfile,
                ),
                const SizedBox(height: 16),
                
                // Cancel button
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Gets the initials from a name
  String _getInitials(String name) {
    List<String> nameParts = name.split(' ');
    String initials = '';
    
    if (nameParts.length > 1) {
      initials = nameParts[0][0] + nameParts[1][0];
    } else if (nameParts.isNotEmpty) {
      initials = nameParts[0][0];
    }
    
    return initials.toUpperCase();
  }
} 