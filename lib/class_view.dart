import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ClassViewPage extends StatefulWidget {
  const ClassViewPage({super.key});

  @override
  State<ClassViewPage> createState() => _ClassViewPageState();
}

class _ClassViewPageState extends State<ClassViewPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late Future<List<Map<String, dynamic>>> _classesFuture;
  String? _role;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadUserAndClasses();
  }

  Future<void> _loadUserAndClasses() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _loadingRole = false);
      return;
    }

    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final role = userDoc.data()?['role']?.toString();

      if (role != 'student' && role != 'teacher') {
        if (!mounted) return;
        setState(() {
          _role = role;
          _loadingRole = false;
        });
        return;
      }

      if (!mounted) return;

      setState(() {
        _role = role;
        _loadingRole = false;
        _classesFuture = _loadClasses(user.uid, role!);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRole = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadClasses(
    String userId,
    String role,
  ) async {
    final List<Map<String, dynamic>> results = [];

    if (role == 'student') {
      final enrollments = await _db
          .collection('class_enrollments')
          .where('studentId', isEqualTo: userId)
          .get();

      for (final enrollment in enrollments.docs) {
        final classId = enrollment.data()['classId']?.toString();
        if (classId == null || classId.isEmpty) continue;

        final classDoc = await _db.collection('classes').doc(classId).get();

        if (!classDoc.exists) continue;

        final data = classDoc.data()!;
        if (data['status'] == 'inactive' || data['status'] == 'archived') {
          continue;
        }

        results.add({'id': classDoc.id, ...data});
      }
    } else if (role == 'teacher') {
      final classSnapshot = await _db
          .collection('classes')
          .where('teacherId', isEqualTo: userId)
          .get();

      for (final doc in classSnapshot.docs) {
        final data = doc.data();

        if (data['status'] == 'inactive' || data['status'] == 'archived') {
          continue;
        }

        results.add({'id': doc.id, ...data});
      }
    }

    results.sort((a, b) {
      final nameA = (a['subjectName'] ?? '').toString().toLowerCase();
      final nameB = (b['subjectName'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return results;
  }

  Future<void> _refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _role == null) return;

    setState(() {
      _classesFuture = _loadClasses(user.uid, _role!);
    });

    await _classesFuture;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Classes')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_role != 'student' && _role != 'teacher') {
      return Scaffold(
        appBar: AppBar(title: const Text('My Classes')),
        body: const Center(
          child: Text('This page is available to Students and Teachers only.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load classes: ${snapshot.error}'),
              ),
            );
          }

          final classes = snapshot.data ?? [];

          if (classes.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 150),
                  Icon(
                    Icons.school_outlined,
                    size: 65,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _role == 'student'
                          ? 'You are not enrolled in any classes yet.'
                          : 'You have no assigned classes yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Your classes will appear here once assigned.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _role == 'student' ? 'Enrolled Classes' : 'Assigned Classes',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF245A91),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...classes.map((classData) => _buildClassCard(classData)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> data) {
    final schedules = data['schedules'] is List
        ? data['schedules'] as List
        : [];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClassDetailsPage(classData: data, role: _role!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFEAF2FA),
                    child: Icon(Icons.menu_book, color: Color(0xFF245A91)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['subjectName']?.toString() ?? 'Unnamed Subject',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${data['subjectCode'] ?? ''} • ${data['shift'] ?? 'Shift not specified'}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Color(0xFF245A91),
                  ),
                ],
              ),
              const Divider(height: 25),
              if (_role == 'student')
                _infoRow(
                  Icons.person_outline,
                  'Teacher',
                  data['teacherName']?.toString().isNotEmpty == true
                      ? data['teacherName'].toString()
                      : 'Not assigned',
                ),
              _infoRow(
                Icons.calendar_month,
                'Schedules',
                '${schedules.length} weekly meeting(s)',
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'View Class Details',
                  style: TextStyle(
                    color: Color(0xFF245A91),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 19, color: Colors.grey[700]),
          const SizedBox(width: 9),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class ClassDetailsPage extends StatelessWidget {
  final Map<String, dynamic> classData;
  final String role;

  const ClassDetailsPage({
    super.key,
    required this.classData,
    required this.role,
  });

  static const Color primaryColor = Color(0xFF245A91);

  @override
  Widget build(BuildContext context) {
    final schedules = classData['schedules'] is List
        ? (classData['schedules'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Class Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.school, size: 38, color: primaryColor),
                  const SizedBox(height: 12),
                  Text(
                    classData['subjectName']?.toString() ?? 'Unnamed Subject',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${classData['subjectCode'] ?? ''} • ${classData['shift'] ?? ''}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const Divider(height: 28),
                  _detailRow(
                    'Teacher',
                    classData['teacherName']?.toString() ?? 'Not assigned',
                  ),
                  _detailRow(
                    'Subject Code',
                    classData['subjectCode']?.toString() ?? 'Not specified',
                  ),
                  _detailRow(
                    'Shift',
                    classData['shift']?.toString() ?? 'Not specified',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Class Schedule and Room',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 10),
          if (schedules.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No schedule has been assigned.'),
              ),
            )
          else
            ...schedules.map((schedule) {
              final start = schedule['startTimeMinutes'];
              final end = schedule['endTimeMinutes'];

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEAF2FA),
                    child: Icon(Icons.calendar_month, color: primaryColor),
                  ),
                  title: Text(
                    schedule['dayOfWeek']?.toString() ?? 'Day not specified',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${_formatMinutes(start)} - ${_formatMinutes(end)}',
                  ),
                  trailing: const Icon(Icons.meeting_room, color: primaryColor),
                  isThreeLine: false,
                ),
              );
            }),
          const SizedBox(height: 18),
          Text(
            role == 'student' ? 'My Classmates' : 'Enrolled Students',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 10),
          _EnrolledStudentsList(
            classId: classData['id'].toString(),
            role: role,
          ),
        ],
      ),
    );
  }

  static String _formatMinutes(dynamic value) {
    if (value is! num) return 'Not specified';

    final minutes = value.toInt();
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final time = TimeOfDay(hour: hour, minute: minute);

    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minuteText = minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';

    return '$hour12:$minuteText $period';
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrolledStudentsList extends StatelessWidget {
  final String classId;
  final String role;

  const _EnrolledStudentsList({required this.classId, required this.role});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Text('Please log in to view enrolled students.');
    }

    // Teachers can retrieve the full roster of their assigned class.
    // Students can retrieve only their own enrollment under the current rules.
    final query = db
        .collection('class_enrollments')
        .where('classId', isEqualTo: classId);

    final Future<QuerySnapshot<Map<String, dynamic>>> enrollmentsFuture =
        role == 'teacher'
        ? query.get()
        : query.where('studentId', isEqualTo: user.uid).get();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: enrollmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Text('Unable to load students: ${snapshot.error}');
        }

        final enrollments = snapshot.data?.docs ?? [];

        if (enrollments.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No students are currently enrolled.'),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.people, color: Color(0xFF245A91)),
                title: const Text(
                  'Currently Enrolled',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Text(
                  '${enrollments.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF245A91),
                  ),
                ),
              ),
              const Divider(height: 1),
              ...enrollments.map((enrollment) {
                final studentId =
                    enrollment.data()['studentId']?.toString() ?? '';

                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: db.collection('users').doc(studentId).get(),
                  builder: (context, studentSnapshot) {
                    if (studentSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const ListTile(
                        leading: CircleAvatar(child: Icon(Icons.person)),
                        title: Text('Loading student...'),
                      );
                    }

                    if (studentSnapshot.hasError) {
                      return const ListTile(
                        leading: CircleAvatar(child: Icon(Icons.person)),
                        title: Text('Unable to load student details'),
                      );
                    }

                    final student = studentSnapshot.data?.data();

                    final name =
                        student?['name']?.toString() ??
                        student?['email']?.toString() ??
                        'Student';

                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEAF2FA),
                        child: Icon(Icons.person, color: Color(0xFF245A91)),
                      ),
                      title: Text(name),
                      subtitle: student?['email'] != null
                          ? Text(student!['email'].toString())
                          : null,
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
