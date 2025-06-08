import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../shared/theme/app_colors.dart';
import '../bloc/create_duel/create_duel_bloc.dart';
import '../bloc/create_duel/create_duel_event.dart';
import '../bloc/create_duel/create_duel_state.dart';

class CreateDuelForm extends StatefulWidget {
  const CreateDuelForm({super.key});

  @override
  State<CreateDuelForm> createState() => _CreateDuelFormState();
}

class _CreateDuelFormState extends State<CreateDuelForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _isPublic = true;
  String _duelType = 'Distance';
  double _targetValue = 10.0;
  
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title field
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Duel Title',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Title is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Description field
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          
          // Duel Type Dropdown
          DropdownButtonFormField<String>(
            value: _duelType,
            decoration: const InputDecoration(
              labelText: 'Challenge Type',
              border: OutlineInputBorder(),
            ),
            items: ['Distance', 'Duration', 'Calories', 'Sessions']
                .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _duelType = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Target field
          TextFormField(
            initialValue: _targetValue.toString(),
            decoration: InputDecoration(
              labelText: 'Target Value',
              border: const OutlineInputBorder(),
              suffixText: _getSuffixForDuelType(_duelType),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Target value is required';
              }
              if (double.tryParse(value) == null) {
                return 'Target must be a number';
              }
              return null;
            },
            onChanged: (value) {
              _targetValue = double.tryParse(value) ?? 10.0;
            },
          ),
          const SizedBox(height: 16),
          
          // End Date Picker
          ListTile(
            title: const Text('End Date'),
            subtitle: Text(
              '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() {
                  _endDate = picked;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Public/Private Toggle
          SwitchListTile(
            title: const Text('Public Challenge'),
            subtitle: const Text(
              'Allow anyone to join this challenge',
            ),
            value: _isPublic,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (newValue) {
              setState(() {
                _isPublic = newValue;
              });
            },
          ),
          const SizedBox(height: 24),
          
          // Submit Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Send create duel event
                context.read<CreateDuelBloc>().add(
                      CreateDuelSubmitted(
                        title: _titleController.text,
                        // description: _descriptionController.text, // Removed - not supported by backend yet
                        challengeType: _duelType,
                        targetValue: _targetValue,
                        timeframeHours: (_endDate.difference(DateTime.now()).inHours),
                        maxParticipants: 10, // Default value
                        minParticipants: 2, // Default value
                        startMode: 'auto', // Default value
                        isPublic: _isPublic,
                      ),
                    );
              }
            },
            child: const Text(
              'CREATE DUEL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getSuffixForDuelType(String duelType) {
    switch (duelType) {
      case 'Distance':
        return 'km';
      case 'Duration':
        return 'min';
      case 'Calories':
        return 'kcal';
      default:
        return '';
    }
  }
}
