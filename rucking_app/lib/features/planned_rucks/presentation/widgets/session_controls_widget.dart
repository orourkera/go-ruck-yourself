import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/theme/app_colors.dart';
import 'package:rucking_app/core/theme/app_text_styles.dart';

/// Interactive session controls widget for managing active ruck sessions
class SessionControlsWidget extends StatefulWidget {
  final RuckSession activeSession;
  final bool showQuickActions;
  final bool showEmergencyControls;
  final bool showAdvancedControls;
  final VoidCallback? onPausePressed;
  final VoidCallback? onResumePressed;
  final VoidCallback? onStopPressed;
  final VoidCallback? onMarkWaypointPressed;
  final VoidCallback? onTakePhotoPressed;
  final VoidCallback? onEmergencyPressed;
  final VoidCallback? onShareLocationPressed;
  final VoidCallback? onAdjustSettingsPressed;

  const SessionControlsWidget({
    super.key,
    required this.activeSession,
    this.showQuickActions = true,
    this.showEmergencyControls = true,
    this.showAdvancedControls = false,
    this.onPausePressed,
    this.onResumePressed,
    this.onStopPressed,
    this.onMarkWaypointPressed,
    this.onTakePhotoPressed,
    this.onEmergencyPressed,
    this.onShareLocationPressed,
    this.onAdjustSettingsPressed,
  });

  @override
  State<SessionControlsWidget> createState() => _SessionControlsWidgetState();
}

class _SessionControlsWidgetState extends State<SessionControlsWidget>
    with TickerProviderStateMixin {
  late AnimationController _primaryButtonController;
  late AnimationController _emergencyButtonController;
  late Animation<double> _primaryButtonAnimation;
  late Animation<double> _emergencyPulseAnimation;
  
  bool _showExpandedControls = false;
  bool _showStopConfirmation = false;

  @override
  void initState() {
    super.initState();
    
    _primaryButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _emergencyButtonController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _primaryButtonAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _primaryButtonController,
      curve: Curves.easeInOut,
    ));
    
    _emergencyPulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _emergencyButtonController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.showEmergencyControls) {
      _emergencyButtonController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _primaryButtonController.dispose();
    _emergencyButtonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Main controls row
          _buildMainControls(),
          
          // Quick actions
          if (widget.showQuickActions) ...[
            const SizedBox(height: 16),
            _buildQuickActions(),
          ],
          
          // Advanced controls (expandable)
          if (widget.showAdvancedControls) ...[
            const SizedBox(height: 12),
            _buildAdvancedToggle(),
            
            if (_showExpandedControls) ...[
              const SizedBox(height: 16),
              _buildAdvancedControls(),
            ],
          ],
          
          // Emergency controls
          if (widget.showEmergencyControls) ...[
            const SizedBox(height: 16),
            _buildEmergencyControls(),
          ],
          
          // Stop confirmation dialog
          if (_showStopConfirmation) ...[
            const SizedBox(height: 16),
            _buildStopConfirmation(),
          ],
        ],
      ),
    );
  }

  Widget _buildMainControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Primary action button (Pause/Resume)
        Expanded(
          flex: 2,
          child: AnimatedBuilder(
            animation: _primaryButtonAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _primaryButtonAnimation.value,
                child: _buildPrimaryActionButton(),
              );
            },
          ),
        ),
        
        const SizedBox(width: 16),
        
        // Stop button
        Expanded(
          child: _buildStopButton(),
        ),
      ],
    );
  }

  Widget _buildPrimaryActionButton() {
    final isPaused = widget.activeSession.status == RuckSessionStatus.paused;
    
    return GestureDetector(
      onTapDown: (_) => _primaryButtonController.forward(),
      onTapUp: (_) => _primaryButtonController.reverse(),
      onTapCancel: () => _primaryButtonController.reverse(),
      onTap: _handlePrimaryAction,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPaused 
                ? [AppColors.success, AppColors.success.withOpacity(0.8)]
                : [AppColors.warning, AppColors.warning.withOpacity(0.8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: (isPaused ? AppColors.success : AppColors.warning)
                  .withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPaused ? Icons.play_arrow : Icons.pause,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              isPaused ? 'Resume' : 'Pause',
              style: AppTextStyles.headline6.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopButton() {
    return GestureDetector(
      onTap: _handleStopPress,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.stop,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              'Stop',
              style: AppTextStyles.body2.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildQuickActionButton(
          icon: Icons.add_location,
          label: 'Waypoint',
          onPressed: widget.onMarkWaypointPressed,
          color: AppColors.info,
        ),
        
        _buildQuickActionButton(
          icon: Icons.camera_alt,
          label: 'Photo',
          onPressed: widget.onTakePhotoPressed,
          color: AppColors.primary,
        ),
        
        _buildQuickActionButton(
          icon: Icons.share_location,
          label: 'Share',
          onPressed: widget.onShareLocationPressed,
          color: AppColors.success,
        ),
        
        _buildQuickActionButton(
          icon: Icons.settings,
          label: 'Settings',
          onPressed: widget.onAdjustSettingsPressed,
          color: AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showExpandedControls = !_showExpandedControls;
        });
        HapticFeedback.lightImpact();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Advanced Controls',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _showExpandedControls ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildAdvancedControlButton(
                  icon: Icons.lock,
                  label: 'Lock Screen',
                  onPressed: _handleLockScreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAdvancedControlButton(
                  icon: Icons.volume_off,
                  label: 'Mute Alerts',
                  onPressed: _handleMuteAlerts,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildAdvancedControlButton(
                  icon: Icons.battery_saver,
                  label: 'Battery Saver',
                  onPressed: _handleBatterySaver,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAdvancedControlButton(
                  icon: Icons.visibility_off,
                  label: 'Hide UI',
                  onPressed: _handleHideUI,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyControls() {
    return AnimatedBuilder(
      animation: _emergencyPulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _emergencyPulseAnimation.value,
          child: GestureDetector(
            onTap: _handleEmergencyPress,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.error,
                    AppColors.error.withOpacity(0.8),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'EMERGENCY',
                    style: AppTextStyles.headline6.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStopConfirmation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: AppColors.error,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stop Session?',
                  style: AppTextStyles.subtitle1.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'This will end your current ruck session. All progress will be saved.',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelStopConfirmation,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.textSecondary),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: ElevatedButton(
                  onPressed: _confirmStop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Stop Session'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Event handlers

  void _handlePrimaryAction() {
    HapticFeedback.mediumImpact();
    
    if (widget.activeSession.status == RuckSessionStatus.paused) {
      widget.onResumePressed?.call();
    } else {
      widget.onPausePressed?.call();
    }
  }

  void _handleStopPress() {
    HapticFeedback.heavyImpact();
    setState(() {
      _showStopConfirmation = true;
    });
  }

  void _cancelStopConfirmation() {
    setState(() {
      _showStopConfirmation = false;
    });
  }

  void _confirmStop() {
    HapticFeedback.heavyImpact();
    widget.onStopPressed?.call();
    setState(() {
      _showStopConfirmation = false;
    });
  }

  void _handleEmergencyPress() {
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            const SizedBox(width: 8),
            const Text('Emergency Alert'),
          ],
        ),
        content: const Text(
          'This will send your location to emergency contacts and local services. '
          'Use only in genuine emergencies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onEmergencyPressed?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
  }

  void _handleLockScreen() {
    // TODO: Implement screen lock functionality
    _showFeatureComingSoonSnackbar('Screen Lock');
  }

  void _handleMuteAlerts() {
    // TODO: Implement mute functionality
    _showFeatureComingSoonSnackbar('Mute Alerts');
  }

  void _handleBatterySaver() {
    // TODO: Implement battery saver mode
    _showFeatureComingSoonSnackbar('Battery Saver');
  }

  void _handleHideUI() {
    // TODO: Implement UI hiding functionality
    _showFeatureComingSoonSnackbar('Hide UI');
  }

  void _showFeatureComingSoonSnackbar(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature coming soon!'),
        backgroundColor: AppColors.info,
      ),
    );
  }
}
