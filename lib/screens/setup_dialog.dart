import 'package:flutter/material.dart';
import 'package:stock_count/config.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SetupDialog extends StatefulWidget {
  final bool isFirstLaunch;

  const SetupDialog({Key? key, this.isFirstLaunch = true}) : super(key: key);

  @override
  _SetupDialogState createState() => _SetupDialogState();
}

class _SetupDialogState extends State<SetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    setState(() => _isLoading = true);

    try {
      final baseUrl = await AppConfig.baseUrl;
      final clientId = await AppConfig.clientId;

      setState(() {
        _baseUrlController.text = baseUrl;
        _clientIdController.text = clientId;
      });
    } catch (e) {
      print("Error loading config: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        await AppConfig.saveConfig(
          baseUrl: _baseUrlController.text.trim(),
          clientId: _clientIdController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate success
        }
      } catch (e) {
        print("Error saving config: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save configuration: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _openFrappeOAuthDocs() async {
    const url = 'https://frappeframework.com/docs/v14/user/en/api/oauth';
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open documentation')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isFirstLaunch
                            ? 'Welcome to Stock Taking App!'
                            : 'App Configuration',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Please configure the app to connect to your Frappe server:',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),

                      // Base URL field
                      TextFormField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          labelText: 'Base URL',
                          hintText: 'https://your-frappe-server.com',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.link),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the base URL';
                          }
                          if (!value.startsWith('http')) {
                            return 'URL must start with http:// or https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Client ID field
                      TextFormField(
                        controller: _clientIdController,
                        decoration: InputDecoration(
                          labelText: 'Client ID',
                          hintText: 'Enter OAuth Client ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.vpn_key),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the client ID';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // OAuth Setup Instructions
                      ExpansionTile(
                        title: const Text('How to set up OAuth in Frappe'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '1. Go to your Frappe server and create a new OAuth Client:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '   • Navigate to: Integrations > OAuth Client > New',
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '2. Fill in the following details:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '   • App Name: Stock Taking App\n'
                                  '   • Skip Authorization: Check this box\n'
                                  '   • Redirect URIs: stockcount://oauth2redirect\n'
                                  '   • Default Redirect URI: stockcount://oauth2redirect\n'
                                  '   • Grant Type: Authorization Code\n'
                                  '   • Response Type: Code',
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '3. Save the OAuth Client and copy the Client ID',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: _openFrappeOAuthDocs,
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text(
                                      'Open Frappe OAuth Documentation'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!widget.isFirstLaunch)
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _saveConfig,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Save Configuration',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }
}
