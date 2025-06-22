import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:provider/provider.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
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
  final String? eventId;
  final String? eventTitle;
  
  const CreateSessionScreen({
    Key? key,
    this.eventId,
    this.eventTitle,
  }) : super(key: key);

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
  
  // Controller and flag for custom ruck weight input
  final TextEditingController _customRuckWeightController = TextEditingController();
  bool _showCustomRuckWeightInput = false;
  
  // Add loading state variable
  bool _isCreating = false;
  bool _isLoading = true;
  double _selectedRuckWeight = 0.0;
  
  // Event context state variables
  String? _eventId;
  String? _eventTitle;

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
        // Double check the conversion for standard (imperial) weights is correct
        double weightForApiKg = _ruckWeight;
        
        // Debug log the exact weight being saved
        AppLogger.debug('Creating session with ruck weight: ${weightForApiKg.toStringAsFixed(2)} kg');
        AppLogger.debug('Original selection was: ${_displayRuckWeight} ${_preferMetric ? "kg" : "lbs"}');
        
        // Prepare request data for creation
        Map<String, dynamic> createRequestData = {
          'ruck_weight_kg': weightForApiKg,
        };
        
        // Add event context if creating session for an event
        if (_eventId != null) {
          createRequestData['event_id'] = _eventId;
          createRequestData['session_type'] = 'event_ruck';
        }
        
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
        
        // Try to create online session first, but fall back quickly to offline
        try {
          AppLogger.info('Attempting to create online session...');
          final createResponse = await apiClient.post('/rucks', createRequestData).timeout(Duration(milliseconds: 800));

          if (!mounted) return;
          
          // Check if response has the correct ID key
          if (createResponse == null || createResponse['id'] == null) {
            throw Exception('Invalid response from server when creating session');
          }
          
          // Extract ruck ID from response
          ruckId = createResponse['id'].toString();
          AppLogger.info('✅ Created online session: $ruckId');
        } catch (e) {
          // Any error (network, timeout, etc.) immediately goes to offline mode
          AppLogger.warning('Failed to create online session, proceeding offline: $e');
          
          // Create offline session ID
          ruckId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
          AppLogger.info('🔄 Created offline session: $ruckId');
        }
        
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
          userWeightKg: userWeightKg, // Pass the calculated userWeightKg (double)
          notes: null, // Set to null, assuming no dedicated notes input for session args here. Adjust if a notes field exists.
          plannedDuration: plannedDuration,
          eventId: _eventId, // Use _eventId from route arguments, not widget.eventId
        );
        
        AppLogger.sessionCompletion('Creating session with event context', context: {
          'event_id': _eventId,
          'event_title': _eventTitle,
          'ruck_weight_kg': _ruckWeight,
          'planned_duration_seconds': plannedDuration,
        });
        
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
    
    // Extract event context from constructor parameters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use constructor parameters instead of route arguments
      final eventId = widget.eventId;
      final eventTitle = widget.eventTitle;
      
      print('📋 Create session screen received constructor args: eventId=$eventId, eventTitle=$eventTitle');
      
      if (eventId != null && eventTitle != null) {
        setState(() {
          _eventId = eventId;
          _eventTitle = eventTitle;
        });
        print('📋 Set event context: _eventId = $_eventId, _eventTitle = $_eventTitle');
      } else {
        print('📋 No event arguments provided');
      }
    });
    
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
          _displayRuckWeight = _preferMetric ? lastWeightKg : (lastWeightKg * AppConfig.kgToLbs);
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
    _customRuckWeightController.dispose();
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
          (weightValue == 0 && isSelected) ? 'HIKE' : (isMetric ? (weightValue == 0 ? '0 kg' : '${weightValue.toStringAsFixed(1)} kg') : (weightValue == 0 ? '0 lbs' : '${weightValue.round()} lbs')),
          textAlign: TextAlign.center,
          style: AppTextStyles.statValue.copyWith(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : (isSelected ? Colors.white : Colors.black),
            height: 1.0,
          ),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
      if (selected) {
        HapticFeedback.heavyImpact();
        setState(() {
          // Store the correctly converted weight in kg for the API
          _selectedRuckWeight = weightInKg;
          _ruckWeight = weightInKg;
          // Store the display weight in the user's preferred unit
          _displayRuckWeight = weightValue;
          
          AppLogger.debug('Selected weight chip: ${weightValue} ${isMetric ? "kg" : "lbs"}');
          AppLogger.debug('Converted to: ${_ruckWeight.toStringAsFixed(2)} kg for storage');
        });
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
                  HapticFeedback.heavyImpact();
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
        title: Text(_eventTitle != null ? 'Start Event Ruck' : 'New Ruck Session'),
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
                // Event banner if creating session for an event
                if (_eventTitle != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Event Ruck Session',
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _eventTitle!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
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
                const SizedBox(height: 8),

                // Link to toggle custom ruck weight input
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _showCustomRuckWeightInput = !_showCustomRuckWeightInput;
                        if (!_showCustomRuckWeightInput) {
                          // Clear any entered custom weight when hiding
                          _customRuckWeightController.clear();
                        }
                      });
                    },
                    child: Text(
                      _showCustomRuckWeightInput ? 'Hide custom weight' : 'Enter custom weight',
                      style: AppTextStyles.bodySmall.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                if (_showCustomRuckWeightInput) ...[
                  const SizedBox(height: 8),
                  CustomTextField(
                    controller: _customRuckWeightController,
                    label: 'Custom Ruck Weight ($weightUnit)',
                    hint: 'e.g. 37',
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.fitness_center_outlined,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (!_showCustomRuckWeightInput) return null; // Skip if not shown
                      if (value == null || value.isEmpty) {
                        return 'Please enter a weight';
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return sessionInvalidWeight;
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          if (_preferMetric) {
                            _ruckWeight = parsed;
                            _displayRuckWeight = parsed;
                          } else {
                            _ruckWeight = parsed / AppConfig.kgToLbs;
                            _displayRuckWeight = parsed;
                          }
                          _selectedRuckWeight = _ruckWeight;
                        });
                      }
                    },
                  ),
                ],
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
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        _plannedDuration = null;
                      } else {
                        final parsed = int.tryParse(value);
                        _plannedDuration = (parsed != null && parsed > 0) ? parsed : null;
                      }
                    });
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
                      HapticFeedback.mediumImpact();
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