import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'where_am_i_screen.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _name1Controller = TextEditingController();
  final TextEditingController _phone1Controller = TextEditingController();
  
  final TextEditingController _name2Controller = TextEditingController();
  final TextEditingController _phone2Controller = TextEditingController();
  
  final TextEditingController _name3Controller = TextEditingController();
  final TextEditingController _phone3Controller = TextEditingController();

  Future<void> _saveContacts() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('contact_name_1', _name1Controller.text);
      await prefs.setString('contact_phone_1', _phone1Controller.text);
      
      await prefs.setString('contact_name_2', _name2Controller.text);
      await prefs.setString('contact_phone_2', _phone2Controller.text);
      
      await prefs.setString('contact_name_3', _name3Controller.text);
      await prefs.setString('contact_phone_3', _phone3Controller.text);
      
      await prefs.setBool('contacts_saved', true);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WhereAmIScreen()),
        );
      }
    }
  }

  Widget _buildContactField(String title, TextEditingController nameCtrl, TextEditingController phoneCtrl) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.isEmpty ? 'Required' : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts Setup'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please set 3 emergency contacts before continuing. These will be used for the SOS feature.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildContactField('Contact 1', _name1Controller, _phone1Controller),
              _buildContactField('Contact 2', _name2Controller, _phone2Controller),
              _buildContactField('Contact 3', _name3Controller, _phone3Controller),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveContacts,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save & Continue', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
