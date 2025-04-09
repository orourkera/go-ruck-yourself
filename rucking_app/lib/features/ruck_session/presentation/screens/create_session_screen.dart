import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
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
  final _userWeightController = TextEditingController();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  double _ruckWeight = AppConfig.defaultRuckWeight;
  int _plannedDuration = 60; // Default 60 minutes
  bool _preferMetric = false; // Default to standard
  
  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _durationController.text = _plannedDuration.toString();
    
    // Get user's unit preference and load last session data
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      _preferMetric = authState.user.preferMetric;
      _loadLastSessionData();
    } else {
      _isLoading = false;
    }
  }

  /// Load the last session data
  Future<void> _loadLastSessionData() async {
    try {
      final apiClient = GetIt.instance<ApiClient>();
      final response = await apiClient.get('/api/rucks?limit=1');
      
      List<dynamic> sessions = [];
      
      if (response == null) {
        // No data
      } else if (response is List) {
        sessions = response;
      } else if (response is Map && response.containsKey('data') && response['data'] is List) {
        sessions = response['data'] as List;
      }
      
      if (sessions.isNotEmpty) {
        final lastSession = sessions[0];
        final lastWeight = lastSession['weight_kg'];
        
        if (lastWeight != null) {
          setState(() {
            _ruckWeight = lastWeight.toDouble();
            // Convert to lbs if user preference is not metric
            if (!_preferMetric) {
              _ruckWeight = _ruckWeight * 2.20462;
            }
          });
        }
      }
      
      // Hide loading indicator
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      // Ignore errors when loading last session data
      debugPrint('Error loading last session data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Snaps the current weight to the nearest predefined weight option
  void _snapToNearestWeight() {
    final weightOptions = _preferMetric 
        ? [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]
        : [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0];
    
    double closestWeight = weightOptions.first;
    double smallestDifference = (_ruckWeight - closestWeight).abs();
    
    for (double weight in weightOptions) {
      double difference = (_ruckWeight - weight).abs();
      if (difference < smallestDifference) {
        smallestDifference = difference;
        closestWeight = weight;
      }
    }
    
    _ruckWeight = closestWeight;
  }

  @override
  void dispose() {
    _userWeightController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Creates and starts a new ruck session
  void _createSession() async {
    if (_formKey.currentState!.validate()) {
      // First check if user is authenticated
      final authState = context.read<AuthBloc>().state;
      if (authState is! Authenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You must be logged in to create a session'),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Log In',
              onPressed: () {
                // Navigate to login screen
                Navigator.of(context).pushNamed('/login');
              },
            ),
          ),
        );
        return;
      }
      
      try {
        // Show loading indicator
        setState(() {
          _isCreating = true;
        });

        // Convert weight to kg if user is using imperial units
        double ruckWeightKg = _preferMetric ? _ruckWeight : _ruckWeight / 2.20462;

        // Prepare request data
        Map<String, dynamic> requestData = {
          'weight_kg': ruckWeightKg,
          'notes': _notesController.text.isEmpty ? '' : _notesController.text,
        };
        
        // Add user's weight (now required)
        double userWeightKg = _preferMetric 
            ? double.parse(_userWeightController.text) 
            : double.parse(_userWeightController.text) / 2.20462; // Convert lbs to kg
        requestData['user_weight_kg'] = userWeightKg;

        // Create session in the backend
        final apiClient = GetIt.instance<ApiClient>();
        final response = await apiClient.post('/api/rucks', requestData);

        if (!mounted) return;
        
        // Check if response has session_id
        if (response == null || !response.containsKey('session_id')) {
          throw Exception('Invalid response from server, missing session_id');
        }
        
        // Extract ruck ID from response
        final ruckId = response['session_id'].toString();
        
        // Navigate to active session screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveSessionScreen(
              ruckId: ruckId,
              ruckWeight: _ruckWeight,
              userWeight: double.parse(_userWeightController.text),
              plannedDuration: _durationController.text.isEmpty ? 
                  0 : int.parse(_durationController.text),
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
    final weightUnit = _preferMetric ? 'kg' : 'lbs';
    
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
              
              // Quick ruck weight selection
              Text(
                'Ruck Weight ($weightUnit)',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Weight is used to calculate calories burned during your ruck',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: _preferMetric 
                          ? [5, 10, 15, 20, 25, 30, 35, 40].map((weight) => 
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _buildWeightChip(weight.toDouble()),
                              )
                            ).toList()
                          : [10, 20, 30, 40, 50, 60, 70, 80].map((weight) => 
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _buildWeightChip(weight.toDouble()),
                              )
                            ).toList(),
                      ),
              ),
              const SizedBox(height: 32),
              
              // User weight field (optional)
              CustomTextField(
                controller: _userWeightController,
                label: 'Your Weight ($weightUnit)',
                hint: 'Enter your weight',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.monitor_weight_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your weight';
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
              
              // Start session button - orange and full width
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    'START SESSION', 
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    )
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isCreating ? null : _createSession,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a chip for quick ruck weight selection
  Widget _buildWeightChip(double weight) {
    final isSelected = _ruckWeight == weight;
    final weightUnit = _preferMetric ? 'kg' : 'lbs';
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _ruckWeight = weight;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey,
            width: 1,
          ),
        ),
        child: Text(
          '${weight.toInt()} $weightUnit',
          style: AppTextStyles.button.copyWith(
            color: isSelected ? Colors.white : AppColors.textDark,
          ),
        ),
      ),
    );
  }
} 