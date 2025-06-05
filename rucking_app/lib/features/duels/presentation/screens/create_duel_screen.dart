import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/create_duel/create_duel_bloc.dart';
import '../bloc/create_duel/create_duel_event.dart';
import '../bloc/create_duel/create_duel_state.dart';
import '../widgets/create_duel_form.dart';
import 'duel_detail_screen.dart';
import '../../../../shared/theme/app_colors.dart';

class CreateDuelScreen extends StatefulWidget {
  const CreateDuelScreen({super.key});

  @override
  State<CreateDuelScreen> createState() => _CreateDuelScreenState();
}

class _CreateDuelScreenState extends State<CreateDuelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetValueController = TextEditingController();
  final _timeframeController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _inviteEmailsController = TextEditingController();

  String _selectedChallengeType = 'distance';
  bool _isPublic = true;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetValueController.dispose();
    _timeframeController.dispose();
    _maxParticipantsController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _inviteEmailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Duel'),
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => context.read<CreateDuelBloc>().add(ResetCreateDuel()),
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: BlocConsumer<CreateDuelBloc, CreateDuelState>(
        listener: (context, state) {
          if (state is CreateDuelSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
            // Navigate to the created duel detail
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => DuelDetailScreen(duelId: state.createdDuel.id)),
            );
          } else if (state is CreateDuelError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is CreateDuelInitial) {
            _resetForm();
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader('Duel Information'),
                  const SizedBox(height: 16),
                  
                  _buildTitleField(state),
                  const SizedBox(height: 16),
                  
                  _buildDescriptionField(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Challenge Details'),
                  const SizedBox(height: 16),
                  
                  _buildChallengeTypeDropdown(),
                  const SizedBox(height: 16),
                  
                  _buildTargetValueField(state),
                  const SizedBox(height: 16),
                  
                  _buildTimeframeField(state),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Participation Settings'),
                  const SizedBox(height: 16),
                  
                  _buildMaxParticipantsField(state),
                  const SizedBox(height: 16),
                  
                  _buildVisibilityToggle(),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('Location (Optional)'),
                  const SizedBox(height: 16),
                  
                  _buildLocationFields(),
                  const SizedBox(height: 24),
                  
                  if (!_isPublic) ...[
                    _buildSectionHeader('Invite Friends'),
                    const SizedBox(height: 16),
                    _buildInviteEmailsField(state),
                    const SizedBox(height: 24),
                  ],
                  
                  _buildCreateButton(state),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildTitleField(CreateDuelState state) {
    final hasError = state is CreateDuelFormInvalid && state.errors.containsKey('title');
    
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Duel Title *',
        hintText: 'Enter a catchy title for your duel',
        errorText: hasError ? state.errors['title'] : null,
        border: const OutlineInputBorder(),
      ),
      maxLength: 100,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Title is required';
        }
        return null;
      },
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      decoration: const InputDecoration(
        labelText: 'Description (Optional)',
        hintText: 'Add more details about this duel...',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
      maxLength: 500,
    );
  }

  Widget _buildChallengeTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedChallengeType,
      decoration: const InputDecoration(
        labelText: 'Challenge Type *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'distance', child: Text('Distance (km)')),
        DropdownMenuItem(value: 'time', child: Text('Time (minutes)')),
        DropdownMenuItem(value: 'elevation', child: Text('Elevation (meters)')),
        DropdownMenuItem(value: 'power_points', child: Text('Power Points')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedChallengeType = value!;
        });
      },
    );
  }

  Widget _buildTargetValueField(CreateDuelState state) {
    final hasError = state is CreateDuelFormInvalid && state.errors.containsKey('targetValue');
    
    return TextFormField(
      controller: _targetValueController,
      decoration: InputDecoration(
        labelText: 'Target Value *',
        hintText: _getTargetValueHint(),
        errorText: hasError ? state.errors['targetValue'] : null,
        border: const OutlineInputBorder(),
        suffixText: _getTargetValueUnit(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Target value is required';
        }
        final numValue = double.tryParse(value);
        if (numValue == null || numValue <= 0) {
          return 'Enter a valid positive number';
        }
        return null;
      },
    );
  }

  Widget _buildTimeframeField(CreateDuelState state) {
    final hasError = state is CreateDuelFormInvalid && state.errors.containsKey('timeframeHours');
    
    return TextFormField(
      controller: _timeframeController,
      decoration: InputDecoration(
        labelText: 'Timeframe (Hours) *',
        hintText: 'How long will this duel last?',
        errorText: hasError ? state.errors['timeframeHours'] : null,
        border: const OutlineInputBorder(),
        suffixText: 'hours',
      ),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Timeframe is required';
        }
        final numValue = int.tryParse(value);
        if (numValue == null || numValue <= 0) {
          return 'Enter a valid number of hours';
        }
        return null;
      },
    );
  }

  Widget _buildMaxParticipantsField(CreateDuelState state) {
    final hasError = state is CreateDuelFormInvalid && state.errors.containsKey('maxParticipants');
    
    return TextFormField(
      controller: _maxParticipantsController,
      decoration: InputDecoration(
        labelText: 'Max Participants *',
        hintText: 'Maximum number of participants',
        errorText: hasError ? state.errors['maxParticipants'] : null,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Max participants is required';
        }
        final numValue = int.tryParse(value);
        if (numValue == null || numValue < 2) {
          return 'At least 2 participants required';
        }
        return null;
      },
    );
  }

  Widget _buildVisibilityToggle() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Duel Visibility',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(_isPublic ? 'Public Duel' : 'Private Duel'),
              subtitle: Text(
                _isPublic 
                    ? 'Anyone can discover and join this duel'
                    : 'Only invited users can join this duel',
              ),
              value: _isPublic,
              onChanged: (value) {
                setState(() {
                  _isPublic = value;
                });
              },
              activeColor: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _cityController,
            decoration: const InputDecoration(
              labelText: 'City',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            controller: _stateController,
            decoration: const InputDecoration(
              labelText: 'State',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInviteEmailsField(CreateDuelState state) {
    final hasError = state is CreateDuelFormInvalid && state.errors.containsKey('inviteeEmails');
    
    return TextFormField(
      controller: _inviteEmailsController,
      decoration: InputDecoration(
        labelText: 'Invite by Email',
        hintText: 'Enter email addresses separated by commas',
        errorText: hasError ? state.errors['inviteeEmails'] : null,
        border: const OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }

  Widget _buildCreateButton(CreateDuelState state) {
    final isLoading = state is CreateDuelSubmitting;
    
    return ElevatedButton(
      onPressed: isLoading ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              'Create Duel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  String _getTargetValueHint() {
    switch (_selectedChallengeType) {
      case 'distance':
        return 'e.g., 10.5';
      case 'time':
        return 'e.g., 60';
      case 'elevation':
        return 'e.g., 500';
      case 'power_points':
        return 'e.g., 1000';
      default:
        return '';
    }
  }

  String _getTargetValueUnit() {
    switch (_selectedChallengeType) {
      case 'distance':
        return 'km';
      case 'time':
        return 'min';
      case 'elevation':
        return 'm';
      case 'power_points':
        return 'pts';
      default:
        return '';
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final targetValue = double.parse(_targetValueController.text);
      final timeframeHours = int.parse(_timeframeController.text);
      final maxParticipants = int.parse(_maxParticipantsController.text);
      
      List<String>? inviteeEmails;
      if (!_isPublic && _inviteEmailsController.text.trim().isNotEmpty) {
        inviteeEmails = _inviteEmailsController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      // First validate the form
      context.read<CreateDuelBloc>().add(ValidateCreateDuelForm(
        title: _titleController.text,
        challengeType: _selectedChallengeType,
        targetValue: targetValue,
        timeframeHours: timeframeHours,
        maxParticipants: maxParticipants,
        inviteeEmails: inviteeEmails,
      ));

      // Then submit if validation passes
      context.read<CreateDuelBloc>().add(CreateDuelSubmitted(
        title: _titleController.text,
        challengeType: _selectedChallengeType,
        targetValue: targetValue,
        timeframeHours: timeframeHours,
        maxParticipants: maxParticipants,
        isPublic: _isPublic,
        description: _descriptionController.text.isNotEmpty 
            ? _descriptionController.text 
            : null,
        creatorCity: _cityController.text.isNotEmpty 
            ? _cityController.text 
            : null,
        creatorState: _stateController.text.isNotEmpty 
            ? _stateController.text 
            : null,
        inviteeEmails: inviteeEmails,
      ));
    }
  }

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();
    _targetValueController.clear();
    _timeframeController.clear();
    _maxParticipantsController.clear();
    _cityController.clear();
    _stateController.clear();
    _inviteEmailsController.clear();
    setState(() {
      _selectedChallengeType = 'distance';
      _isPublic = true;
    });
  }
}
