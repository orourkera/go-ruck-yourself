import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:provider/provider.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/active_session_page.dart';
import 'package:rucking_app/features/ruck_session/presentation/screens/countdown_page.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';
import 'package:rucking_app/core/error_messages.dart';
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

  final ScrollController _weightScrollController = ScrollController();

  double _ruckWeight = AppConfig.defaultRuckWeight;
  double _displayRuckWeight = 0.0; // Will be set in kg or lbs based on preference
  int? _plannedDuration; // Default is now empty
  bool _preferMetric = false; // Default to standard
  
  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;
  double _selectedRuckWeight = 0.0;

  late final VoidCallback _durationListener;

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
      _selectedRuckWeight = lastWeightKg; // Ensure selectedRuckWeight is synced with ruckWeight
      
      // Update display weight based on preference
      if (_preferMetric) {
        _displayRuckWeight = _ruckWeight;
      } else {
        _displayRuckWeight = _ruckWeight * AppConfig.kgToLbs;
      }
      
      
      
      // Load last used duration (might be null if not previously set)
      int? lastDurationMinutes = prefs.getInt('lastSessionDurationMinutes');
      _plannedDuration = lastDurationMinutes;
      if (lastDurationMinutes != null) {
        _durationController.text = lastDurationMinutes.toString();
      }
      
      // Load user's body weight (if previously saved)
      String? lastUserWeight = prefs.getString('lastUserWeight');
      if (lastUserWeight != null && lastUserWeight.isNotEmpty) {
        _userWeightController.text = lastUserWeight;
      }

    } catch (e) {
      
      // Fallback to defaults on error
      _ruckWeight = AppConfig.defaultRuckWeight;
      _durationController.text = '30'; // Default duration on error
    } finally {
      setState(() {
        _isLoading = false;
      });
      // Make sure we trigger a UI update with the loaded weights
      Future.delayed(Duration.zero, () {
        if (mounted) {
          setState(() {
            // Force synchronization
            _selectedRuckWeight = _ruckWeight;
            
          });
        }
      });
    }
  }

  /// Saves the last used ruck weight to SharedPreferences
  Future<void> _saveLastWeight(double weightKg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lastRuckWeightKg', weightKg);
    
  }

  /// Saves the last used session duration to SharedPreferences
  Future<void> _saveLastDuration(int durationMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSessionDurationMinutes', durationMinutes);
    
  }
  
  /// Saves the user's body weight to SharedPreferences
  Future<void> _saveUserWeight(String weight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastUserWeight', weight);
    
  }

  /// Creates and starts a new ruck session
  void _createSession() async {
    if (_formKey.currentState!.validate()) {
      final authState = context.read<AuthBloc>().state;
      if (authState is! Authenticated) {
        StyledSnackBar.showError(
          context: context,
          message: 'You must be logged in to create a session',
          duration: const Duration(seconds: 3),
        );
        // Navigate to login screen after a brief delay
        Future.delayed(const Duration(milliseconds: 1500), () {
          Navigator.of(context).pushNamed('/login');
        });
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
        
        
        // Prepare request data for creation
        Map<String, dynamic> createRequestData = {
          'ruck_weight_kg': weightForApiKg,
        };
        
        // Add user's weight (required)
        final userWeightRaw = _userWeightController.text;
        if (userWeightRaw.isEmpty) {
            throw Exception(sessionUserWeightRequired); // Use centralized error message
        }
        double userWeightKg = _preferMetric 
            ? double.parse(userWeightRaw) 
            : double.parse(userWeightRaw) / 2.20462; // Convert lbs to kg
        createRequestData['weight_kg'] = userWeightKg;
        
        // --- Ensure planned duration is included ---
        if (_plannedDuration != null && _plannedDuration! > 0) {
          createRequestData['planned_duration_minutes'] = _plannedDuration;
        }
        // --- End planned duration addition ---

        // --- Add user_id for Supabase RLS ---
        createRequestData['user_id'] = authState.user.userId;
        // --- End user_id ---
        
        // ---- Step 1: Create session in the backend ----
        
        final apiClient = GetIt.instance<ApiClient>();
        final createResponse = await apiClient.post('/rucks', createRequestData);

        if (!mounted) return;
        
        // Check if response has the correct ID key
        if (createResponse == null || createResponse['id'] == null) {
          
          throw Exception('Invalid response from server when creating session');
        }
        
        // Extract ruck ID from response
        ruckId = createResponse['id'].toString();
        
        

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
        

        
        // Delay and then navigate without resetting chip state
        await Future.delayed(Duration(milliseconds: 500));
        // Convert planned duration (minutes) to seconds; null means no planned duration
        final int? plannedDuration = _plannedDuration != null ? _plannedDuration! * 60 : null;
        
        // Create session args that will be passed to both CountdownPage and later to ActiveSessionPage
        final sessionArgs = ActiveSessionArgs(
          ruckWeight: _ruckWeight,
          notes: _userWeightController.text.isNotEmpty ? _userWeightController.text : null,
          plannedDuration: plannedDuration,
        );
        
        // Navigate to CountdownPage which will handle the countdown and transition
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CountdownPage(args: sessionArgs),
          ),
        );
      } catch (e) {
        
        if (mounted) {
          StyledSnackBar.showError(
            context: context,
            message: e.toString().contains(sessionUserWeightRequired)
              ? sessionUserWeightRequired
              : 'Failed to create/start session: $e',
            duration: const Duration(seconds: 3),
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
    
    _loadDefaults();
    _selectedRuckWeight = _ruckWeight; // initialize with default selected weight
    // Load metric preference and **body weight** from AuthBloc state
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      setState(() {
        _preferMetric = authState.user.preferMetric;
        // NEW: Pre-populate user weight from profile if available
        final double? profileWeightKg = authState.user.weightKg;
        if (profileWeightKg != null) {
          final String weightText = _preferMetric
              ? profileWeightKg.toStringAsFixed(1)
              : (profileWeightKg * 2.20462).toStringAsFixed(1);
          // Only assign if controller is empty so we don't override SharedPrefs load
          if (_userWeightController.text.isEmpty) {
            _userWeightController.text = weightText;
          }
        }
        // Update display weight based on new preference
        _displayRuckWeight = _preferMetric ? _ruckWeight : (_ruckWeight * AppConfig.kgToLbs);
        
      });
      
      // Ensure the last ruck weight is loaded and set as selected
      _loadLastRuckWeight();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedWeight());
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
          
        });
        // Force a UI rebuild to ensure the chip is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToSelectedWeight();
        });
      } else {
        
      }
    });
    // Attach listener after controllers are ready
    _durationListener = () {
      final text = _durationController.text;
      if (text.isEmpty) {
        setState(() {
          _plannedDuration = null;
        });
      } else {
        final minutes = int.tryParse(text);
        setState(() {
          _plannedDuration = (minutes != null && minutes > 0) ? minutes : null;
        });
      }
    };
    _durationController.addListener(_durationListener);
  }

  void _scrollToSelectedWeight() {
    final List<double> currentWeightOptions = _preferMetric 
        ? AppConfig.metricWeightOptions 
        : AppConfig.standardWeightOptions;
    final selectedIndex = currentWeightOptions.indexWhere((w) {
      final weightInKg = _preferMetric ? w : w / AppConfig.kgToLbs;
      return (weightInKg - _selectedRuckWeight).abs() < (_preferMetric ? 0.01 : 0.1);
    });
    if (selectedIndex != -1 && _weightScrollController.hasClients) {
      // Width of each chip item including separator spacing
      const double itemExtent = 60.0; // 52 chip + 8 separator – keep in sync with separatorBuilder

      double offset;
      if (selectedIndex == currentWeightOptions.length - 1) {
        // Ensure we scroll completely to the end so last chip is fully visible
        offset = _weightScrollController.position.maxScrollExtent;
      } else {
        offset = (selectedIndex * itemExtent)
            .clamp(0.0, _weightScrollController.position.maxScrollExtent);
      }

      // Animate after current frame to avoid "jump" during first build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_weightScrollController.hasClients) {
          _weightScrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  // Load last saved ruck weight from SharedPreferences
  Future<void> _loadLastRuckWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final lastWeightKg = prefs.getDouble('lastRuckWeightKg');
    if (lastWeightKg != null) {
      setState(() {
        _ruckWeight = lastWeightKg;
        _selectedRuckWeight = lastWeightKg;
        _displayRuckWeight = _preferMetric ? lastWeightKg : (lastWeightKg * AppConfig.kgToLbs);
        
      });
    }
  }

  @override
  void dispose() {
    _weightScrollController.dispose();
    _userWeightController.dispose();
    _durationController.removeListener(_durationListener);
    _durationController.dispose();
    _durationFocusNode.dispose();
    super.dispose();
  }

  /// Snaps the current weight to the nearest predefined weight option
  void _snapToNearestWeight() {
    List<double> weightOptions = [];
    
    if (_preferMetric) {
      // Metric options (kg)
      weightOptions = AppConfig.metricWeightOptions;
    } else {
      // Imperial options (lbs)
      weightOptions = AppConfig.standardWeightOptions;
    }
    
    // Find the nearest weight option
    double? closestOption;
    double minDifference = double.infinity;
    
    for (var option in weightOptions) {
      final optionInKg = _preferMetric ? option : option / AppConfig.kgToLbs;
      // Use a slightly more forgiving comparison for imperial weights due to conversion rounding
      final difference = (optionInKg - _ruckWeight).abs();
      
      if (difference < minDifference) {
        minDifference = difference;
        closestOption = option;
      }
    }
    
    if (closestOption != null) {
      setState(() {
        if (_preferMetric) {
          _ruckWeight = closestOption!;
          _displayRuckWeight = closestOption!;
        } else {
          _ruckWeight = closestOption! / AppConfig.kgToLbs;
          _displayRuckWeight = closestOption!;
        }
        // Make sure _selectedRuckWeight is also updated
        _selectedRuckWeight = _ruckWeight;
        
        
      });
    }
  }

  Widget _buildWeightChip(double weightValue, bool isMetric) {
    double weightInKg = isMetric ? weightValue : weightValue / AppConfig.kgToLbs;
    final bool isSelected = isMetric
        ? (weightInKg - _selectedRuckWeight).abs() < 0.01
        : (weightInKg - _selectedRuckWeight).abs() < 0.1;
    
    
    return ChoiceChip(
      label: Container(
        height: 36,
        alignment: Alignment.center,
        child: Text(
          weightValue == 0 ? 'HIKE' : (isMetric ? '${weightValue.toStringAsFixed(1)} kg' : '${weightValue.round()} lbs'),
          textAlign: TextAlign.center,
          style: AppTextStyles.statValue.copyWith(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : (isSelected ? Colors.white : Colors.black),
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
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('lastRuckWeightKg', weightInKg);
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedWeight());
        }
      },
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: isSelected
        ? Theme.of(context).primaryColor
        : (Theme.of(context).brightness == Brightness.dark ? AppColors.error : AppColors.backgroundLight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : null,
        fontWeight: FontWeight.bold,
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
                  style: AppTextStyles.titleLarge, // headline6 -> titleLarge
                ),
                const SizedBox(height: 24),
                
                // Quick ruck weight selection
                Text(
                  'Ruck Weight ($weightUnit)',
                  style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold), // subtitle1 -> titleMedium
                ),
                const SizedBox(height: 8),
                Text(
                  'Weight is used to calculate calories burned during your ruck',
                  style: AppTextStyles.bodySmall.copyWith( // caption -> bodySmall
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
                          controller: _weightScrollController,
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
                      return sessionInvalidWeight;
                    }
                    if (double.parse(value) <= 0) {
                      return sessionInvalidWeight;
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
                        return sessionInvalidDuration;
                      }
                      if (int.parse(value) <= 0) {
                        return sessionInvalidDuration;
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
                      style: AppTextStyles.labelLarge.copyWith( // button -> labelLarge
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