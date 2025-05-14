import 'package:flutter/material.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';

/// Screen for editing user profile information
class EditProfileScreen extends StatefulWidget {
  final User user;
  final bool preferMetric;

  const EditProfileScreen({
    Key? key,
    required this.user,
    required this.preferMetric,
  }) : super(key: key);

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  bool _isLoading = false;
  String? _selectedGender;

  // Constants for conversion
  static const double kgToLbs = 2.20462;
  static const double cmToInches = 0.393701;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    
    // Initialize weight controller with display value
    double displayWeight = 0;
    if (widget.user.weightKg != null) {
        displayWeight = widget.preferMetric 
            ? widget.user.weightKg! 
            : widget.user.weightKg! * kgToLbs;
    }
    _weightController = TextEditingController(text: displayWeight > 0 ? displayWeight.toStringAsFixed(1) : '');

    // Initialize height controller with display value
    double displayHeight = 0;
     if (widget.user.heightCm != null) {
        displayHeight = widget.preferMetric 
            ? widget.user.heightCm! 
            : widget.user.heightCm! * cmToInches;
     }
    _heightController = TextEditingController(text: displayHeight > 0 ? displayHeight.toStringAsFixed(1) : '');
    
    // Initialize gender selection
    _selectedGender = widget.user.gender;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // Prepare data, converting back to metric if needed
      double? weightKg;
      if (_weightController.text.isNotEmpty) {
          final weightVal = double.tryParse(_weightController.text);
          if (weightVal != null) {
              // If user prefers metric, do nothing. If standard, convert lbs to kg before saving
              weightKg = widget.preferMetric ? weightVal : weightVal * 0.453592;
          }
      }

      double? heightCm;
      if (_heightController.text.isNotEmpty) {
          final heightVal = double.tryParse(_heightController.text);
           if (heightVal != null) {
              heightCm = widget.preferMetric ? heightVal : heightVal / cmToInches;
           }
      }
      
      context.read<AuthBloc>().add(
            AuthUpdateProfileRequested(
              username: _usernameController.text,
              weightKg: weightKg,
              heightCm: heightCm,
              preferMetric: widget.preferMetric,
              gender: _selectedGender,
            ),
          );

      // Listen for state changes to pop or show error
      final streamSub = context.read<AuthBloc>().stream.listen((state) {
         if (state is Authenticated) {
            if (mounted) {
               Navigator.pop(context); // Pop on success
            }
         } else if (state is AuthError) {
             if (mounted) {
                StyledSnackBar.showError(
                  context: context,
                  message: "Update failed: ${state.message}",
                  duration: const Duration(seconds: 3),
                );
               setState(() {
                 _isLoading = false; // Re-enable button on error
               });
            }
         } 
      });
      // Cancel subscription after a delay or on dispose to avoid memory leaks
      // This part is simplified, real implementation might need more robust handling
       Future.delayed(Duration(seconds: 5), () => streamSub.cancel());
    }
  }

  @override
  Widget build(BuildContext context) {
    final weightUnit = widget.preferMetric ? 'kg' : 'lbs';
    final heightUnit = widget.preferMetric ? 'cm' : 'inches'; // Use inches for imperial height
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Removed profile picture circle avatar placeholder
              const SizedBox(height: 20),
              CustomTextField(
                controller: _usernameController,
                label: 'Username',
                hint: 'Enter your username',
                prefixIcon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your username';
                  }
                  // Optional: Add other username validation (length, characters etc.)
                  return null;
                },
              ),
              const SizedBox(height: 20),
              CustomTextField(
                controller: _weightController,
                label: 'Weight ($weightUnit) - Optional',
                hint: 'Enter your weight',
                prefixIcon: Icons.monitor_weight_outlined,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                   FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                validator: (value) {
                    if (value != null && value.isNotEmpty) {
                        final number = double.tryParse(value);
                        if (number == null) {
                           return 'Please enter a valid number';
                        }
                        if (number <= 0) {
                           return 'Weight must be positive';
                        }
                    }
                   return null;
                },
              ),
              const SizedBox(height: 20),
              CustomTextField(
                controller: _heightController,
                label: 'Height ($heightUnit) - Optional',
                hint: 'Enter your height',
                prefixIcon: Icons.height_outlined,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                   FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                 validator: (value) {
                    if (value != null && value.isNotEmpty) {
                        final number = double.tryParse(value);
                        if (number == null) {
                           return 'Please enter a valid number';
                        }
                        if (number <= 0) {
                           return 'Height must be positive';
                        }
                    }
                   return null;
                },
              ),
              const SizedBox(height: 20),
              // Gender dropdown
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[800] 
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: InputBorder.none,
                  ),
                  items: [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                    DropdownMenuItem(value: null, child: Text('Prefer not to say')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedGender = value;
                    });
                  },
                  hint: Text('Select your gender'),
                  isExpanded: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Weight, height, and gender information help calculate calories more accurately and personalize your experience.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CustomButton(
                text: 'Save Profile',
                onPressed: _saveProfile,
                isLoading: _isLoading,
                icon: Icons.save_outlined,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                    'Cancel',
                     style: AppTextStyles.labelLarge.copyWith(
                       color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
                     ),
                 ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 