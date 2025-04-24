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

  double _ruckWeight = AppConfig.defaultRuckWeight;
  int? _plannedDuration; // Default is now empty
  bool _preferMetric = false; // Default to standard
  
  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Get user's unit preference and load last session data
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      _preferMetric = authState.user.preferMetric;
      // --- Populate user weight if available ---
      final userWeightKg = authState.user.weightKg;
      if (userWeightKg != null && userWeightKg > 0) {
        if (_preferMetric) {
          _userWeightController.text = userWeightKg.toStringAsFixed(1);
        } else {
          // Convert kg to lbs (1 kg = 2.20462 lbs)
          final weightLbs = userWeightKg * 2.20462;
          _userWeightController.text = weightLbs.toStringAsFixed(1);
        }
      }
      // --- End populate user weight ---
      _loadLastSessionData();
    } else {
      _isLoading = false;
    }
  }

  /// Load the last session data
  Future<void> _loadLastSessionData() async {
    try {
      final apiClient = GetIt.instance<ApiClient>();
      debugPrint('Loading last session data from /rucks?limit=1');
      final response = await apiClient.get('/rucks?limit=1');
      
      debugPrint('Response type: ${response.runtimeType}');
      if (response is Map) {
        debugPrint('Response keys: ${response.keys.toList()}');
      }
      
      List<dynamic> sessions = [];
      
      if (response == null) {
        debugPrint('Response is null');
      } else if (response is List) {
        debugPrint('Response is a List with ${response.length} items');
        sessions = response;
      } else if (response is Map && response.containsKey('data') && response['data'] is List) {
        debugPrint('Response is a Map with "data" key containing a List of ${(response['data'] as List).length} items');
        sessions = response['data'] as List;
      } else if (response is Map && response.containsKey('sessions') && response['sessions'] is List) {
        debugPrint('Response is a Map with "sessions" key containing a List of ${(response['sessions'] as List).length} items');
        sessions = response['sessions'] as List;
      } else if (response is Map && response.containsKey('items') && response['items'] is List) {
        debugPrint('Response is a Map with "items" key containing a List of ${(response['items'] as List).length} items');
        sessions = response['items'] as List;
      } else if (response is Map && response.containsKey('results') && response['results'] is List) {
        debugPrint('Response is a Map with "results" key containing a List of ${(response['results'] as List).length} items');
        sessions = response['results'] as List;
      } else if (response is Map) {
        // Last resort: check for the first key that contains a List
        for (var key in response.keys) {
          if (response[key] is List) {
            debugPrint('Found List under key "$key" with ${(response[key] as List).length} items');
            sessions = response[key] as List;
            break;
          }
        }
        
        if (sessions.isEmpty) {
          debugPrint('Unexpected response format: $response');
        }
      } else {
        debugPrint('Unknown response type: ${response.runtimeType}');
      }
      
      if (sessions.isNotEmpty) {
        debugPrint('Found ${sessions.length} sessions, using first one');
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
      } else {
        debugPrint('No sessions found');
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
    super.dispose();
  }

  /// Creates and starts a new ruck session
  void _createSession() async {
    if (_formKey.currentState!.validate()) {
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
      
      // Set loading state immediately
      setState(() {
        _isCreating = true;
      });

      String? ruckId;
      try {
        // Convert weight to kg if user is using imperial units
        double ruckWeightKg = _preferMetric ? _ruckWeight : _ruckWeight / 2.20462;

        // Prepare request data for creation
        Map<String, dynamic> createRequestData = {
          'ruck_weight_kg': ruckWeightKg,
        };
        
        // Add user's weight (required)
        final userWeightRaw = _userWeightController.text;
        if (userWeightRaw.isEmpty) {
            throw Exception('User weight is required'); // Or handle validation earlier
        }
        double userWeightKg = _preferMetric 
            ? double.parse(userWeightRaw) 
            : double.parse(userWeightRaw) / 2.20462; // Convert lbs to kg
        createRequestData['user_weight_kg'] = userWeightKg;

        // --- Add user_id for Supabase RLS ---
        createRequestData['user_id'] = authState.user.userId;
        // --- End user_id ---
        
        // ---- Step 1: Create session in the backend ----
        debugPrint('Creating session via POST /rucks...');
        final apiClient = GetIt.instance<ApiClient>();
        final createResponse = await apiClient.post('/rucks', createRequestData);

        if (!mounted) return;
        
        // Check if response has the correct ID key
        if (createResponse == null || createResponse['id'] == null) {
          debugPrint('Invalid response from POST /rucks: $createResponse');
          throw Exception('Invalid response from server when creating session');
        }
        
        // Extract ruck ID from response
        ruckId = createResponse['id'].toString();
        debugPrint('Session created successfully with ID: $ruckId');

        // ---- Step 2: Start the created session ----
        final startEndpoint = '/rucks/$ruckId/start';
        debugPrint('Starting session via POST $startEndpoint...');
        final startResponse = await apiClient.post(startEndpoint, {}); // No body needed for start
        
        if (!mounted) return;
        
        // Minimal check for start response (can be more robust)
        if (startResponse == null || !(startResponse is Map && startResponse.containsKey('message'))) {
             debugPrint('Invalid response from POST $startEndpoint: $startResponse');
             // Decide if we should throw or just log a warning
             // throw Exception('Failed to confirm session start on server.');
             print("Warning: Could not confirm session start on server, but proceeding.");
        }
        
        debugPrint('Session started successfully on backend.');
        
        // ---- Step 3: Navigate to active session screen ----
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveSessionScreen(
              ruckId: ruckId!, // Now we know ruckId is not null here
              ruckWeight: _ruckWeight,
              userWeight: double.parse(_userWeightController.text),
              plannedDuration: _durationController.text.isEmpty ? 
                  0 : int.parse(_durationController.text),
            ),
          ),
        );
      } catch (e) {
        debugPrint('Error during session creation/start: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create/start session: $e'),
              backgroundColor: AppColors.error,
            ),
          );
          // Only set creating to false on error, success leads to navigation
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