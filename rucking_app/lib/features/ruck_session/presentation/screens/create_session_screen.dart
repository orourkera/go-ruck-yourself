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
import 'package:rucking_app/core/services/location_service.dart';
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
  double _selectedRuckWeight = 0.0;

  /// Loads preferences and last used values (ruck weight and duration)
  Future<void> _loadDefaults() async {
    setState(() { _isLoading = true; });
    try {
      final prefs = await SharedPreferences.getInstance();
      // Do not override _preferMetric if it will be set by AuthBloc
      if (!(context.read<AuthBloc>().state is Authenticated)) {
        _preferMetric = prefs.getBool('preferMetric') ?? false;
      }

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
        
        // Log the weight value being saved to the database
        debugPrint('Saving ruck weight in kg: $weightForApiKg');
        
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
        
        // --- Ensure planned duration is included ---
        if (_plannedDuration != null && _plannedDuration! > 0) {
          createRequestData['planned_duration_minutes'] = _plannedDuration;
        } else if (_durationController.text.isNotEmpty && int.tryParse(_durationController.text) != null) {
          createRequestData['planned_duration_minutes'] = int.parse(_durationController.text);
        }
        // --- End planned duration addition ---

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
        debugPrint('Extracted ruckId: $ruckId');
        debugPrint('Session created successfully with ID: $ruckId');

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
        
        // Perform session preparation/validation without resetting _ruckWeight or _displayRuckWeight
        // Log current state for debugging
        debugPrint('Creating session with weight: $_ruckWeight, display: $_displayRuckWeight');

        debugPrint('Creating session with selected weight: $_selectedRuckWeight');
        // Delay and then navigate without resetting chip state
        await Future.delayed(Duration(milliseconds: 500));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => ActiveSessionBloc(
                apiClient: GetIt.instance<ApiClient>(),
                locationService: GetIt.instance<LocationService>(),
              ),
              child: ActiveSessionScreen(
                ruckId: ruckId!,
                ruckWeight: _ruckWeight,
                displayRuckWeight: _preferMetric ? _ruckWeight : _displayRuckWeight,
                userWeight: double.parse(_userWeightController.text),
                plannedDuration: _plannedDuration,
                preferMetric: _preferMetric,
              ),
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

  String _getDisplayWeight() {
    if (_preferMetric) {
      return '${_ruckWeight.toStringAsFixed(1)} kg';
    } else {
      final lbs = (_ruckWeight * AppConfig.kgToLbs).round();
      return '$lbs lbs';
    }
  }

  @override
  void initState() {
    super.initState();
    // Log the metric preference to verify it's set correctly
    debugPrint('CreateSessionScreen: User metric preference is $_preferMetric');
    _loadDefaults();
    _selectedRuckWeight = _ruckWeight; // initialize with default selected weight
    // Load metric preference from AuthBloc state
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      setState(() {
        _preferMetric = authState.user.preferMetric;
        // Update display weight based on new preference
        _displayRuckWeight = _preferMetric ? _ruckWeight : (_ruckWeight * AppConfig.kgToLbs);
        debugPrint('CreateSessionScreen: Weight display updated to $_displayRuckWeight');
      });
      debugPrint('CreateSessionScreen: Updated metric preference from AuthBloc to $_preferMetric');
    }
    _durationFocusNode.addListener(() {
    });
    // Restore last selected ruck weight and ensure UI reflects it
    SharedPreferences.getInstance().then((prefs) {
      final lastWeightKg = prefs.getDouble('lastRuckWeightKg');
      if (lastWeightKg != null) {
        setState(() {
          _ruckWeight = lastWeightKg;
          _displayRuckWeight = _preferMetric ? _ruckWeight : (_ruckWeight * AppConfig.kgToLbs);
          // Explicitly log to verify state update
          debugPrint('Restored ruck weight: $_ruckWeight kg, display: $_displayRuckWeight');
        });
        // Force a UI rebuild to ensure the chip is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('UI rebuild triggered to reflect restored weight: $_ruckWeight kg');
        });
      } else {
        debugPrint('No last ruck weight found in SharedPreferences');
      }
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
    double weightInKg = isMetric ? weightValue : weightValue / AppConfig.kgToLbs;
    final bool isSelected = (weightInKg - _selectedRuckWeight).abs() < 0.01;

    // Log for debugging
    debugPrint('Building chip for weightInKg: $weightInKg, current _ruckWeight: $_ruckWeight');
    debugPrint('Chip for weight $weightInKg isSelected: $isSelected');

    return ChoiceChip(
      label: Container(
        height: 36, // match chip height
        alignment: Alignment.center,
        child: Text(
          isMetric
              ? '${weightValue.toStringAsFixed(1)} kg'
              : '${weightValue.round()} lbs',
          textAlign: TextAlign.center,
          style: AppTextStyles.statValue.copyWith(
            color: isSelected ? Colors.white : Colors.black,
            height: 1.0,
          ),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) async {
        if (selected) {
          setState(() {
            _ruckWeight = weightInKg;
            _displayRuckWeight = isMetric ? weightValue : weightValue;
            _selectedRuckWeight = weightInKg;
          });
          // Persist selected weight
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('lastRuckWeightKg', weightInKg);
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String weightUnit = _preferMetric ? 'kg' : 'lbs';
    // Determine the correct list for the chips
    final List<double> currentWeightOptions = _preferMetric 
        ? AppConfig.metricWeightOptions 
        : AppConfig.standardWeightOptions;
    debugPrint('CreateSessionScreen: Building UI at ${DateTime.now().millisecondsSinceEpoch}, Metric preference: $_preferMetric, Weight options: $currentWeightOptions');
    
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
                  height: 40,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: currentWeightOptions.length,
                          itemBuilder: (context, index) {
                            final weightValue = currentWeightOptions[index];
                            return _buildWeightChip(weightValue, _preferMetric);
                          },
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                        ),
                ),
                const SizedBox(height: 16),
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
                      return null;
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
                    FocusScope.of(context).unfocus();
                    if (!_isCreating) _createSession();
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