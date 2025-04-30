import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:provider/provider.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_screen.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
  final FocusNode _durationFocusNode = FocusNode();

  double _ruckWeight = AppConfig.defaultRuckWeight;
  double _displayRuckWeight = 0.0; // Will be set in kg or lbs based on preference
  int? _plannedDuration; // Default is now empty
  bool _preferMetric = false; // Default to standard
  
  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;

  /// Loads preferences and last used values (ruck weight and duration)
  Future<void> _loadDefaults() async {
    setState(() { _isLoading = true; });
    try {
      final prefs = await SharedPreferences.getInstance();
      _preferMetric = prefs.getBool('preferMetric') ?? false;

      // Load last used weight (KG)
      double lastWeightKg = prefs.getDouble('lastRuckWeightKg') ?? AppConfig.defaultRuckWeight;
      _ruckWeight = lastWeightKg;
      // Update display weight to match unit preference so the correct chip appears selected
      _displayRuckWeight = _preferMetric
          ? _ruckWeight
          : double.parse((_ruckWeight * AppConfig.kgToLbs).toStringAsFixed(1));

      // Load last used duration (minutes)
      int lastDurationMinutes = prefs.getInt('lastSessionDurationMinutes') ?? 30; // Default to 30 mins
      _durationController.text = lastDurationMinutes.toString();
      
      // Load user's body weight (if previously saved)
      String? lastUserWeight = prefs.getString('lastUserWeight');
      if (lastUserWeight != null && lastUserWeight.isNotEmpty) {
        _userWeightController.text = lastUserWeight;
      }

    } catch (e) {
      debugPrint('Error loading defaults: $e');
      // Fallback to defaults on error
      _ruckWeight = AppConfig.defaultRuckWeight;
      _durationController.text = '30'; // Default duration on error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Saves the last used ruck weight to SharedPreferences
  Future<void> _saveLastWeight(double weightKg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lastRuckWeightKg', weightKg);
    debugPrint('Saved last ruck weight (KG): $weightKg');
  }

  /// Saves the last used session duration to SharedPreferences
  Future<void> _saveLastDuration(int durationMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSessionDurationMinutes', durationMinutes);
    debugPrint('Saved last session duration (minutes): $durationMinutes');
  }
  
  /// Saves the user's body weight to SharedPreferences
  Future<void> _saveUserWeight(String weight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastUserWeight', weight);
    debugPrint('Saved user body weight: $weight');
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
        // Weight is stored internally in KG
        double weightForApiKg = _ruckWeight;
        
        // Prepare request data for creation
        Map<String, dynamic> createRequestData = {
          'ruck_weight_kg': weightForApiKg,
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
        
        // Save the used weight (always in KG) to SharedPreferences on success
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lastRuckWeightKg', weightForApiKg);

        // Save the user's entered body weight
        _saveUserWeight(_userWeightController.text);
        
        // Save duration if entered
        if (_durationController.text.isNotEmpty) {
          int duration = int.parse(_durationController.text);
          _plannedDuration = duration;
          await _saveLastDuration(duration);
        }
        
        // ---- Step 3: Navigate to active session screen ----
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveSessionScreen(
              ruckId: ruckId!, // Now we know ruckId is not null here
              ruckWeight: _ruckWeight,
              displayRuckWeight: _displayRuckWeight,
              userWeight: double.parse(_userWeightController.text),
              plannedDuration: _durationController.text.isEmpty ? 
                  0 : int.parse(_durationController.text),
              preferMetric: _preferMetric,
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
  void initState() {
    super.initState();
    _loadDefaults();
    _durationFocusNode.addListener(() {
    });
  }

  @override
  void dispose() {
    _userWeightController.dispose();
    _durationController.dispose();
    _durationFocusNode.dispose();
    super.dispose();
  }

  /// Snaps the current weight to the nearest predefined weight option
  void _snapToNearestWeight() {
    final isMetric = _preferMetric;
    final weightOptions = isMetric 
        ? AppConfig.metricWeightOptions 
        : AppConfig.standardWeightOptions;
  
    double comparisonWeight = _ruckWeight;
    if (!isMetric) {
      comparisonWeight = _ruckWeight * AppConfig.kgToLbs;
    }

    double closestWeightOption = weightOptions.first;
    double smallestDifference = (comparisonWeight - closestWeightOption).abs();
    int closestIndex = 0; // Keep track of the index

    for (int i = 0; i < weightOptions.length; i++) {
      double weight = weightOptions[i];
      double difference = (comparisonWeight - weight).abs();
      if (difference < smallestDifference) {
        smallestDifference = difference;
        closestWeightOption = weight;
        closestIndex = i;
      }
    }
  
    // Ensure internal weight is the corresponding KG value
    _ruckWeight = AppConfig.metricWeightOptions[closestIndex]; 
    
    // Also update the display weight based on user preference
    _displayRuckWeight = _preferMetric ? _ruckWeight : AppConfig.standardWeightOptions[closestIndex];
  }

  /// Builds a chip for quick ruck weight selection
  Widget _buildWeightChip(double weightValue, bool isMetric) {
    // Determine the actual KG value this chip represents
    double weightInKg;
    
    if (isMetric) {
      weightInKg = weightValue;
    } else {
      // Convert lbs to kg directly for accurate comparison
      weightInKg = weightValue / AppConfig.kgToLbs;
    }

    // Check if this chip's KG value matches the selected internal KG weight
    // Use a small tolerance for floating point comparisons
    final bool isSelected = (weightInKg - _ruckWeight).abs() < 0.01;

    return ChoiceChip(
      label: Text(
        '${weightValue.toStringAsFixed(1)} ${isMetric ? "kg" : "lbs"}',
        style: TextStyle(
          fontSize: 14, // Reduce font size slightly
          color: isSelected 
              ? (Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white) 
              : (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark),
        ),
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            // Update internal _ruckWeight with the KG value of the selected chip
            _ruckWeight = weightInKg;
            
            // Store the exact display weight value that was selected
            _displayRuckWeight = weightValue;
          });
        }
      },
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.backgroundDark : AppColors.backgroundLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade400,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Reduce padding
    );
  }

  @override
  Widget build(BuildContext context) {
    final String weightUnit = _preferMetric ? 'kg' : 'lbs';
    // Determine the correct list for the chips
    final List<double> currentWeightOptions = _preferMetric 
        ? AppConfig.metricWeightOptions 
        : AppConfig.standardWeightOptions;
        
    final keyboardActionsConfig = KeyboardActionsConfig(
      actions: [
        KeyboardActionsItem(
          focusNode: _durationFocusNode,
          toolbarButtons: [
            (node) => TextButton(
                  onPressed: () {
                    node.unfocus();
                    if (!_isCreating) _createSession();
                  },
                  child: const Text('Done'),
                ),
          ],
        ),
      ],
      nextFocus: false,
    );
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Ruck Session'),
        centerTitle: true,
      ),
      body: KeyboardActions(
        config: keyboardActionsConfig,
        child: SingleChildScrollView(
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
                  style: AppTextStyles.subtitle1.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Weight is used to calculate calories burned during your ruck',
                  style: AppTextStyles.caption.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF728C69) : AppColors.textDarkSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40, // Reduced height for the chip list
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none, // Make sure the ListView doesn't overflow
                          itemCount: currentWeightOptions.length,
                          itemBuilder: (context, index) {
                            final weightValue = currentWeightOptions[index];
                            return _buildWeightChip(weightValue, _preferMetric);
                          },
                          separatorBuilder: (context, index) => const SizedBox(width: 8), // Reduced spacing between chips
                        ),
                ),
                const SizedBox(height: 16), // Single spacing is enough
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
                      return null; // Make it optional
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
                  focusNode: _durationFocusNode,
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
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).unfocus(); // Hide keyboard
                    if (!_isCreating) _createSession(); // Start session immediately
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
                    onPressed: () {
                      _snapToNearestWeight(); 
                      if (_formKey.currentState!.validate()) {
                        if (!_isCreating) _createSession();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}