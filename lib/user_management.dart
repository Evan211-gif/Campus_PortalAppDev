import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'registered_users.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _institutionalIdController = TextEditingController();

  String _selectedRole = 'student';
  bool _isLoading = false;
  bool _obscurePassword = true;

  String _selectedUserCategory = 'All';

  final _searchController = TextEditingController();
  String _searchQuery = '';

  String get _idLabel =>
      _selectedRole == 'student' ? 'School ID' : 'Teacher ID';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _institutionalIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    FirebaseApp? secondaryApp;
    FirebaseAuth? secondaryAuth;
    User? createdUser;

    try {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final fullName = '$firstName $lastName';
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      final institutionalId = _institutionalIdController.text.trim();
      final role = _selectedRole;

      // Create a separate Firebase app so the Admin
      // remains logged in to the main application.
      secondaryApp = await Firebase.initializeApp(
        name: 'UserCreationApp',
        options: Firebase.app().options,
      );

      secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      createdUser = credential.user;

      if (createdUser == null) {
        throw Exception('Unable to create the authentication account.');
      }

      final uid = createdUser.uid;

      // Save the user record and reserve the ID together.
      // The Firestore transaction prevents duplicate IDs.
      final firestore = FirebaseFirestore.instance;

      final userRef = firestore.collection('users').doc(uid);

      final idRef = firestore
          .collection('institutional_ids')
          .doc(institutionalId);

      await firestore.runTransaction((transaction) async {
        final existingId = await transaction.get(idRef);

        if (existingId.exists) {
          throw Exception('This $_idLabel is already assigned.');
        }

        transaction.set(idRef, {
          'uid': uid,
          'role': role,
          'createdAt': Timestamp.now(),
        });

        transaction.set(userRef, {
          'firstName': firstName,
          'lastName': lastName,
          'name': fullName,
          'email': email,
          'role': role,
          'institutionalId': institutionalId,
          'status': 'active',
          'createdAt': Timestamp.now(),
        });
      });

      if (!mounted) return;

      _firstNameController.clear();
      _lastNameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _institutionalIdController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fullName created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }

      String message;

      switch (error.code) {
        case 'email-already-in-use':
          message = 'This email address is already registered.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'weak-password':
          message = 'Please use a stronger password.';
          break;
        default:
          message = error.message ?? 'Account creation failed.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      // Remove the newly created Auth account if
      // saving the Firestore records failed.
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (secondaryAuth != null) {
        try {
          await secondaryAuth.signOut();
        } catch (_) {}
      }

      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleUserStatus(
    String uid,
    Map<String, dynamic> userData,
  ) async {
    final name = userData['name']?.toString() ?? 'this user';
    final role = userData['role']?.toString() ?? '';
    final currentStatus = userData['status']?.toString() ?? 'active';

    if (role != 'student' && role != 'teacher') return;

    final isActive = currentStatus == 'active';
    final newStatus = isActive ? 'deactivated' : 'active';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isActive ? 'Deactivate User?' : 'Reactivate User?'),
        content: Text(
          isActive
              ? 'Are you sure you want to deactivate $name? '
                    'They will no longer be able to access Campus Portal.'
              : 'Are you sure you want to reactivate $name? '
                    'They will be able to access Campus Portal again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$name has been ${newStatus == 'active' ? 'reactivated' : 'deactivated'}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update account status: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF245A91)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF245A91), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        centerTitle: true,
        backgroundColor: const Color(0xFF245A91),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create New Account',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              Text(
                'Register a new Student or Teacher account.',
                style: TextStyle(color: Colors.grey.shade600),
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('First Name', Icons.person_outline),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the first name.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Last Name', Icons.person_outline),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the last name.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration('Email Address', Icons.email_outlined),
                validator: (value) {
                  if (value == null ||
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(value.trim())) {
                    return 'Please enter a valid email address.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration:
                    _decoration(
                      'Temporary Password',
                      Icons.lock_outline,
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Password must contain at least 6 characters.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              const Text(
                'Account Role',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),

              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: _decoration('Select Role', Icons.badge_outlined),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                ],
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _selectedRole = value;
                            _institutionalIdController.clear();
                          });
                        }
                      },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _institutionalIdController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration:
                    _decoration(
                      _idLabel,
                      Icons.confirmation_number_outlined,
                    ).copyWith(
                      counterText: '',
                      hintText: 'Enter exactly 10 digits',
                    ),
                validator: (value) {
                  if (value == null ||
                      !RegExp(r'^[0-9]{10}$').hasMatch(value)) {
                    return '$_idLabel must contain exactly 10 digits.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 8),

              Text(
                'The $_idLabel must be unique across all accounts.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createUser,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(
                    _isLoading ? 'Creating Account...' : 'Create Account',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF245A91),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisteredUsersPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text(
                    'View Registered Users',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF245A91),
                    side: const BorderSide(color: Color(0xFF245A91)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
