import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_screen.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';

/// Screen for creating a new ruck session
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({Key? key}) : super(key: key);

  @override
  _CreateSessionScreenState createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ruckWeightController = TextEditingController();
  final _userWeightController = TextEditingController();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  double _ruckWeight = AppConfig.defaultRuckWeight;
  int _plannedDuration = 60; // Default 60 minutes
  
  // Add loading state variable
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _ruckWeightController.text = _ruckWeight.toString();
    _durationController.text = _plannedDuration.toString();
  }

  @override
  void dispose() {
    _ruckWeightController.dispose();
    _userWeightController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Creates and starts a new ruck session
  void _createSession() async {
    if (_formKey.currentState!.validate()) {
      try {
        // Show loading indicator
        setState(() {
          _isCreating = true;
        });

        // Create session in the backend
        final apiClient = GetIt.instance<ApiClient>();
        final response = await apiClient.post('/api/rucks', {
          'ruck_weight_kg': double.parse(_ruckWeightController.text),
          'planned_duration_minutes': _durationController.text.isEmpty ? 
              null : int.parse(_durationController.text),
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
        });

        if (!mounted) return;
        
        // Extract ruck ID from response
        final ruckId = response['ruck_id'].toString();
        
        // Navigate to active session screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveSessionScreen(
              ruckId: ruckId,
              ruckWeight: double.parse(_ruckWeightController.text),
              plannedDuration: int.parse(_durationController
                  .text.isEmpty ? '0' : _durationController.text),
              notes: _notesController.text,
            ),
          ),
        );
      } catch (e) {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create session: $e'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _isCreating = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Ruck Session'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section title
              Text(
                'Session Details',
                style: AppTextStyles.headline6,
              ),
              const SizedBox(height: 24),
              
              // Ruck weight field
              CustomTextField(
                controller: _ruckWeightController,
                label: 'Ruck Weight (kg)',
                hint: 'Enter your ruck weight',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.fitness_center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your ruck weight';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  if (double.parse(value) <= 0) {
                    return 'Weight must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // User weight field (optional)
              CustomTextField(
                controller: _userWeightController,
                label: 'Your Weight (kg) - Optional',
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
              const SizedBox(height: 20),
              
              // Planned duration field
              CustomTextField(
                controller: _durationController,
                label: 'Planned Duration (minutes) - Optional',
                hint: 'Enter planned duration',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.timer_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (int.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    if (int.parse(value) <= 0) {
                      return 'Duration must be greater than 0';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Notes field
              CustomTextField(
                controller: _notesController,
                label: 'Notes - Optional',
                hint: 'Add any notes for this session',
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),
              
              // Quick ruck weight presets
              Text(
                'Quick Ruck Weight',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildWeightChip(5),
                  _buildWeightChip(10),
                  _buildWeightChip(15),
                  _buildWeightChip(20),
                  _buildWeightChip(25),
                ],
              ),
              const SizedBox(height: 32),
              
              // Start session button
              CustomButton(
                text: 'Start Session',
                icon: Icons.play_arrow,
                onPressed: _createSession,
                isLoading: _isCreating,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a chip for quick ruck weight selection
  Widget _buildWeightChip(double weight) {
    final isSelected = _ruckWeightController.text == weight.toString();
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _ruckWeightController.text = weight.toString();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey,
            width: 1,
          ),
        ),
        child: Text(
          '${weight.toInt()} kg',
          style: AppTextStyles.body2.copyWith(
            color: isSelected ? Colors.white : AppColors.textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
} 