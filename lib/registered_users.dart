import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RegisteredUsersPage extends StatefulWidget {
  const RegisteredUsersPage({super.key});

  @override
  State<RegisteredUsersPage> createState() => _RegisteredUsersPageState();
}

class _RegisteredUsersPageState extends State<RegisteredUsersPage> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              ? 'Are you sure you want to deactivate $name?'
              : 'Are you sure you want to reactivate $name?',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Users'),
        centerTitle: true,
        backgroundColor: const Color(0xFF245A91),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Users',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'View, search, filter, and manage registered Students and Teachers.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['All', 'Students', 'Teachers'].map((category) {
                final isSelected = _selectedCategory == category;

                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  selectedColor: const Color(0xFF245A91),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),

            const SizedBox(height: 16),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', whereIn: ['student', 'teacher'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Unable to load users.'));
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final users = snapshot.data!.docs;

                  final filteredUsers = users.where((document) {
                    final data = document.data();

                    final role = data['role']?.toString() ?? '';
                    final status = data['status']?.toString() ?? 'active';
                    final isActive = status == 'active';
                    final name = data['name']?.toString().toLowerCase() ?? '';
                    final firstName =
                        data['firstName']?.toString().toLowerCase() ?? '';
                    final lastName =
                        data['lastName']?.toString().toLowerCase() ?? '';
                    final institutionalId =
                        data['institutionalId']?.toString().toLowerCase() ?? '';

                    if (_selectedCategory == 'Students' && role != 'student') {
                      return false;
                    }

                    if (_selectedCategory == 'Teachers' && role != 'teacher') {
                      return false;
                    }

                    if (_searchQuery.isNotEmpty) {
                      final matches =
                          name.contains(_searchQuery) ||
                          firstName.contains(_searchQuery) ||
                          lastName.contains(_searchQuery) ||
                          institutionalId.contains(_searchQuery);

                      if (!matches) return false;
                    }

                    return true;
                  }).toList();

                  if (filteredUsers.isEmpty) {
                    return const Center(
                      child: Text('No matching users found.'),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final document = filteredUsers[index];
                      final data = document.data();

                      final name = data['name']?.toString() ?? 'Unnamed User';
                      final email = data['email']?.toString() ?? '';
                      final role = data['role']?.toString() ?? '';
                      final institutionalId =
                          data['institutionalId']?.toString() ?? '';
                      final status = data['status']?.toString() ?? 'active';
                      final isActive = status == 'active';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF245A91),
                            child: Icon(
                              role == 'student' ? Icons.school : Icons.person,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(email),
                              Text(
                                '${role == 'student' ? 'Student' : 'Teacher'}'
                                ' • ID: $institutionalId',
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isActive ? 'Active' : 'Deactivated',
                                  style: TextStyle(
                                    color: isActive ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: TextButton(
                            onPressed: () =>
                                _toggleUserStatus(document.id, data),
                            child: Text(
                              isActive ? 'Deactivate' : 'Reactivate',
                              style: TextStyle(
                                color: isActive ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
