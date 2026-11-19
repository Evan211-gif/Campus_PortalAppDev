import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ClassManagementPage extends StatefulWidget {
  const ClassManagementPage({super.key});

  @override
  State<ClassManagementPage> createState() => _ClassManagementPageState();
}

class _ClassManagementPageState extends State<ClassManagementPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  Future<bool> _isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data()?['role'] == 'admin';
  }

  // Checks room conflicts and regular-class conflicts for shared students.
  Future<String?> _validateSchedules({
    required String? classId,
    required List<Map<String, dynamic>> schedules,
    Set<String>? selectedStudentIds,
  }) async {
    final classesSnapshot = await _db.collection('classes').get();
    final enrollmentsSnapshot = await _db.collection('class_enrollments').get();

    final eventsSnapshot = await _db.collection('events').get();

    final clubActivitiesSnapshot = await _db
        .collection('club_activities')
        .where('status', isEqualTo: 'approved')
        .get();

    final targetStudentIds =
        selectedStudentIds ??
        enrollmentsSnapshot.docs
            .where((doc) => doc.data()['classId'] == classId)
            .map((doc) => doc.data()['studentId'].toString())
            .toSet();

    final enrollmentsByClass = <String, Set<String>>{};

    for (final enrollment in enrollmentsSnapshot.docs) {
      final data = enrollment.data();
      final enrolledClassId = data['classId']?.toString();
      final studentId = data['studentId']?.toString();

      if (enrolledClassId == null || studentId == null) continue;

      enrollmentsByClass
          .putIfAbsent(enrolledClassId, () => <String>{})
          .add(studentId);
    }

    for (final otherClass in classesSnapshot.docs) {
      if (otherClass.id == classId) continue;

      final otherData = otherClass.data();
      final otherSchedules = otherData['schedules'];

      if (otherSchedules is! List) continue;

      final otherStudentIds = enrollmentsByClass[otherClass.id] ?? <String>{};

      final sharedStudents = targetStudentIds.intersection(otherStudentIds);

      for (final newSchedule in schedules) {
        for (final existingSchedule in otherSchedules) {
          if (existingSchedule is! Map) continue;

          final newDay = newSchedule['dayOfWeek']?.toString();
          final existingDay = existingSchedule['dayOfWeek']?.toString();

          if (newDay != existingDay) continue;

          final newStart = (newSchedule['startTimeMinutes'] as num).toInt();
          final newEnd = (newSchedule['endTimeMinutes'] as num).toInt();

          final oldStart = (existingSchedule['startTimeMinutes'] as num)
              .toInt();
          final oldEnd = (existingSchedule['endTimeMinutes'] as num).toInt();

          final overlaps = newStart < oldEnd && newEnd > oldStart;

          if (!overlaps) continue;

          final newRoom = newSchedule['roomName']?.toString();
          final oldRoom = existingSchedule['roomName']?.toString();

          if (newRoom == oldRoom) {
            return 'Room conflict: $newRoom is already assigned to '
                '${otherData['subjectName'] ?? 'another class'} on $newDay.';
          }

          if (sharedStudents.isNotEmpty) {
            return 'Student schedule conflict: at least one student is '
                'already assigned to ${otherData['subjectName'] ?? 'another class'} '
                'on $newDay during this time.';
          }
        }
      }
    }
    // Check conflicts against Campus Events and approved Club Activities.
    for (final newSchedule in schedules) {
      final newDay = newSchedule['dayOfWeek']?.toString();
      final newRoom = newSchedule['roomName']?.toString();
      final newStart = (newSchedule['startTimeMinutes'] as num).toInt();
      final newEnd = (newSchedule['endTimeMinutes'] as num).toInt();

      // Check Campus Events.
      for (final event in eventsSnapshot.docs) {
        final data = event.data();

        if (data['status'] == 'archived') continue;

        final dateValue = data['date'];
        if (dateValue is! Timestamp) continue;

        final eventDate = dateValue.toDate();
        final eventDay = days[eventDate.weekday - 1];

        if (eventDay != newDay) continue;
        if (data['location']?.toString() != newRoom) continue;

        final oldStart = data['startTimeMinutes'];
        final oldEnd = data['endTimeMinutes'];

        if (oldStart is! num || oldEnd is! num) continue;

        final overlaps = newStart < oldEnd.toInt() && newEnd > oldStart.toInt();

        if (overlaps) {
          return 'Room conflict: $newRoom is already booked for '
              '${data['title'] ?? 'a Campus Event'} on $newDay.';
        }
      }

      // Check approved Club Activities.
      for (final activity in clubActivitiesSnapshot.docs) {
        final data = activity.data();

        final dateValue = data['date'];
        if (dateValue is! Timestamp) continue;

        final activityDate = dateValue.toDate();
        final activityDay = days[activityDate.weekday - 1];

        if (activityDay != newDay) continue;
        if (data['roomName']?.toString() != newRoom) continue;

        final oldStart = data['startTimeMinutes'];
        final oldEnd = data['endTimeMinutes'];

        if (oldStart is! num || oldEnd is! num) continue;

        final overlaps = newStart < oldEnd.toInt() && newEnd > oldStart.toInt();

        if (overlaps) {
          return 'Room conflict: $newRoom is already booked for '
              '${data['activityTitle'] ?? 'a Club Activity'} on $newDay.';
        }
      }
    }
    return null;
  }

  Future<void> _showClassForm({
    String? classId,
    Map<String, dynamic>? existingData,
  }) async {
    final isEditing = classId != null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return _ClassFormDialog(
          isEditing: isEditing,
          existingData: existingData,
        );
      },
    );

    if (result == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final normalizedCode = result['subjectCode']
          .toString()
          .trim()
          .toUpperCase();

      final normalizedShift = result['shift'].toString().trim();

      final schedules = List<Map<String, dynamic>>.from(
        result['schedules'] ?? [],
      );

      final existingClasses = await _db.collection('classes').get();

      final isDuplicate = existingClasses.docs.any((doc) {
        if (doc.id == classId) return false;

        final data = doc.data();

        final existingCode = (data['subjectCode'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        final existingShift = (data['shift'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        return existingCode == normalizedCode &&
            existingShift == normalizedShift.toLowerCase();
      });

      if (isDuplicate) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This subject code already exists for the selected shift.',
            ),
          ),
        );
        return;
      }

      final conflict = await _validateSchedules(
        classId: classId,
        schedules: schedules,
      );

      if (conflict != null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(conflict)));
        return;
      }

      final classData = <String, dynamic>{
        'subjectName': result['subjectName'].toString().trim(),
        'subjectCode': normalizedCode,
        'shift': normalizedShift,
        'schedules': schedules,
        'teacherId': result['teacherId'],
        'teacherName': result['teacherName'],
      };

      if (isEditing) {
        await _db.collection('classes').doc(classId).update({
          ...classData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('classes').add({
          ...classData,
          'status': 'active',
          'studentCount': 0,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Class updated successfully.'
                : 'Class created successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving class: $e')));
    }
  }

  Future<void> _manageStudents(
    String classId,
    Map<String, dynamic> classData,
  ) async {
    try {
      final studentSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      final enrollmentSnapshot = await _db
          .collection('class_enrollments')
          .where('classId', isEqualTo: classId)
          .get();

      final students = studentSnapshot.docs.toList();

      students.sort((a, b) {
        final nameA = (a.data()['name'] ?? '').toString().toLowerCase();
        final nameB = (b.data()['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });

      final selectedStudents = enrollmentSnapshot.docs
          .map((doc) => doc.data()['studentId'].toString())
          .toSet();

      if (!mounted) return;

      final result = await showDialog<Set<String>>(
        context: context,
        builder: (dialogContext) {
          final searchController = TextEditingController();

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final search = searchController.text.toLowerCase();

              final filteredStudents = students.where((student) {
                final data = student.data();
                final name = (data['name'] ?? '').toString().toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();

                return name.contains(search) || email.contains(search);
              }).toList();

              return AlertDialog(
                title: const Text('View / Manage Students'),
                content: SizedBox(
                  width: 450,
                  height: 450,
                  child: Column(
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search student name or email',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current / Selected Students',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${selectedStudents.length} student(s) assigned',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(selectedStudents.clear);
                            },
                            child: const Text('Clear Selection'),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: filteredStudents.isEmpty
                            ? const Center(child: Text('No students found.'))
                            : ListView.builder(
                                itemCount: filteredStudents.length,
                                itemBuilder: (context, index) {
                                  final student = filteredStudents[index];
                                  final data = student.data();
                                  final studentId = student.id;

                                  return CheckboxListTile(
                                    value: selectedStudents.contains(studentId),
                                    title: Text(
                                      (data['name'] ?? 'Unnamed Student')
                                          .toString(),
                                    ),
                                    subtitle: Text(
                                      (data['email'] ?? '').toString(),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: (checked) {
                                      setDialogState(() {
                                        if (checked == true) {
                                          selectedStudents.add(studentId);
                                        } else {
                                          selectedStudents.remove(studentId);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      searchController.dispose();
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final saved = Set<String>.from(selectedStudents);
                      searchController.dispose();
                      Navigator.pop(dialogContext, saved);
                    },
                    child: const Text('Save Assignments'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == null) return;

      final schedules = classData['schedules'] is List
          ? List<Map<String, dynamic>>.from(
              (classData['schedules'] as List).map(
                (item) => Map<String, dynamic>.from(item as Map),
              ),
            )
          : <Map<String, dynamic>>[];

      final conflict = await _validateSchedules(
        classId: classId,
        schedules: schedules,
        selectedStudentIds: result,
      );

      if (conflict != null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(conflict)));
        return;
      }

      final latestEnrollments = await _db
          .collection('class_enrollments')
          .where('classId', isEqualTo: classId)
          .get();

      final batch = _db.batch();
      final existingStudentIds = <String>{};

      for (final enrollment in latestEnrollments.docs) {
        final studentId = enrollment.data()['studentId'].toString();
        existingStudentIds.add(studentId);

        if (!result.contains(studentId)) {
          batch.delete(enrollment.reference);
        }
      }

      for (final studentId in result) {
        if (!existingStudentIds.contains(studentId)) {
          final enrollmentRef = _db
              .collection('class_enrollments')
              .doc('${classId}_$studentId');

          batch.set(enrollmentRef, {
            'classId': classId,
            'studentId': studentId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      batch.update(_db.collection('classes').doc(classId), {
        'studentCount': result.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student assignments saved successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error managing students: $e')));
    }
  }

  Future<void> _deleteClass(String classId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class?'),
        content: const Text(
          'This will also remove all student assignments for this class. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final enrollments = await _db
          .collection('class_enrollments')
          .where('classId', isEqualTo: classId)
          .get();

      if (enrollments.docs.length >= 499) {
        throw Exception(
          'This class has too many assignments to delete in one batch.',
        );
      }

      final batch = _db.batch();

      for (final enrollment in enrollments.docs) {
        batch.delete(enrollment.reference);
      }

      batch.delete(_db.collection('classes').doc(classId));

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class deleted successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error deleting class: $e')));
    }
  }

  Widget _buildClassCard(String classId, Map<String, dynamic> data) {
    final subjectName = data['subjectName'] ?? 'Unnamed Subject';
    final subjectCode = data['subjectCode'] ?? '';
    final shift = data['shift'] ?? 'Shift not assigned';
    final studentCount = data['studentCount'] ?? 0;
    final teacherName = data['teacherName'] ?? 'Not assigned';

    final schedules = data['schedules'] is List
        ? data['schedules'] as List
        : [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject information
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.menu_book)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName.toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$subjectCode • $shift',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showClassForm(classId: classId, existingData: data);
                    } else if (value == 'delete') {
                      _deleteClass(classId);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Class')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Class')),
                  ],
                ),
              ],
            ),

            const Divider(height: 24),

            // Assigned Teacher
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: Color(0xFF245A91),
                ),
                const SizedBox(width: 8),
                const Text('Assigned Teacher: '),
                Expanded(
                  child: Text(
                    teacherName.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Assigned Students
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 20),
                    const SizedBox(width: 8),
                    Text('$studentCount assigned students'),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _manageStudents(classId, data),
                    icon: const Icon(Icons.people, size: 18),
                    label: const Text('View / Manage Students'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Weekly Schedule
            Row(
              children: [
                const Icon(Icons.calendar_month, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${schedules.length} weekly schedule(s)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, adminSnapshot) {
        if (adminSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (adminSnapshot.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Class Management')),
            body: const Center(
              child: Text('You do not have permission to access this page.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Class Management')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showClassForm(),
            icon: const Icon(Icons.add),
            label: const Text('Create Class'),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('classes').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading classes: ${snapshot.error}'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final classes = snapshot.data?.docs ?? [];

              if (classes.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined, size: 60),
                      SizedBox(height: 12),
                      Text(
                        'No classes created yet.',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text('Tap Create Class to get started.'),
                    ],
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Text(
                    'Total Classes: ${classes.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...classes.map((doc) => _buildClassCard(doc.id, doc.data())),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ClassFormDialog extends StatefulWidget {
  final bool isEditing;
  final Map<String, dynamic>? existingData;

  const _ClassFormDialog({required this.isEditing, this.existingData});

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  static const List<String> shifts = ['Morning', 'Afternoon', 'Evening'];

  static const List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> campusLocations = [
    'Classroom 101',
    'Classroom 102',
    'Classroom 103',
    'Classroom 104',
    'Classroom 105',
    'Computer Lab 201',
    'Computer Lab 202',
    'Computer Lab 203',
    'Computer Lab 204',
    'Library',
    'University Gymnasium',
  ];

  late final TextEditingController subjectNameController;
  late final TextEditingController subjectCodeController;

  String? selectedShift;
  String? selectedTeacherId;
  String? selectedTeacherName;

  List<Map<String, dynamic>> teachers = [];
  bool isLoadingTeachers = true;

  final List<_ClassScheduleEntry> schedules = [];

  @override
  void initState() {
    super.initState();
    _loadTeachers();

    subjectNameController = TextEditingController(
      text: widget.existingData?['subjectName'] ?? '',
    );

    subjectCodeController = TextEditingController(
      text: widget.existingData?['subjectCode'] ?? '',
    );

    final existingShift = widget.existingData?['shift']?.toString();
    selectedShift = shifts.contains(existingShift) ? existingShift : null;

    final existingSchedules = widget.existingData?['schedules'];

    if (existingSchedules is List) {
      for (final item in existingSchedules) {
        if (item is! Map) continue;

        final data = Map<String, dynamic>.from(item);

        final day = data['dayOfWeek']?.toString() ?? 'Monday';
        final start = (data['startTimeMinutes'] as num?)?.toInt() ?? 480;
        final end = (data['endTimeMinutes'] as num?)?.toInt() ?? 540;
        final room = data['roomName']?.toString() ?? campusLocations.first;

        if (days.contains(day) &&
            start >= 0 &&
            start < 1440 &&
            end > 0 &&
            end <= 1440 &&
            campusLocations.contains(room)) {
          schedules.add(
            _ClassScheduleEntry(
              dayOfWeek: day,
              startTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
              endTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
              roomName: room,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadTeachers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .get();

      if (!mounted) return;

      setState(() {
        teachers = snapshot.docs.map((doc) {
          final data = doc.data();

          return {
            'id': doc.id,
            'name': data['name'] ?? data['email'] ?? 'Unnamed Teacher',
            'email': data['email'] ?? '',
          };
        }).toList();

        teachers.sort(
          (a, b) => a['name'].toString().toLowerCase().compareTo(
            b['name'].toString().toLowerCase(),
          ),
        );

        final existingId = widget.existingData?['teacherId']?.toString();

        if (existingId != null &&
            teachers.any((teacher) => teacher['id'] == existingId)) {
          selectedTeacherId = existingId;

          selectedTeacherName = teachers
              .firstWhere((teacher) => teacher['id'] == existingId)['name']
              .toString();
        }

        isLoadingTeachers = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingTeachers = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to load teachers: $e')));
    }
  }

  Future<void> _showTeacherSearch() async {
    final searchController = TextEditingController();

    final selectedTeacher = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final search = searchController.text.toLowerCase().trim();

            final filteredTeachers = teachers.where((teacher) {
              final name = teacher['name'].toString().toLowerCase();
              final email = teacher['email'].toString().toLowerCase();

              return name.contains(search) || email.contains(search);
            }).toList();

            return AlertDialog(
              title: const Text('Search Teachers'),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search teacher name or email',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredTeachers.isEmpty
                          ? const Center(child: Text('No teachers found.'))
                          : ListView.builder(
                              itemCount: filteredTeachers.length,
                              itemBuilder: (context, index) {
                                final teacher = filteredTeachers[index];
                                final isSelected =
                                    teacher['id'] == selectedTeacherId;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFEAF2FA),
                                    child: const Icon(
                                      Icons.person,
                                      color: Color(0xFF245A91),
                                    ),
                                  ),
                                  title: Text(teacher['name'].toString()),
                                  subtitle: Text(teacher['email'].toString()),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        )
                                      : null,
                                  onTap: () {
                                    Navigator.pop(dialogContext, teacher);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();

    if (selectedTeacher == null) return;

    setState(() {
      selectedTeacherId = selectedTeacher['id'].toString();
      selectedTeacherName = selectedTeacher['name'].toString();
    });
  }

  @override
  void dispose() {
    subjectNameController.dispose();
    subjectCodeController.dispose();
    super.dispose();
  }

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay time) {
    return time.format(context);
  }

  Future<void> _pickTime(
    _ClassScheduleEntry entry, {
    required bool isStart,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? entry.startTime : entry.endTime,
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        entry.startTime = picked;
      } else {
        entry.endTime = picked;
      }
    });
  }

  void _addSchedule() {
    setState(() {
      schedules.add(
        _ClassScheduleEntry(
          dayOfWeek: 'Monday',
          startTime: const TimeOfDay(hour: 8, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
          roomName: campusLocations.first,
        ),
      );
    });
  }

  void _submit() {
    final name = subjectNameController.text.trim();
    final code = subjectCodeController.text.trim();

    if (name.isEmpty || code.isEmpty || selectedShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all class fields.')),
      );
      return;
    }

    if (schedules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one class schedule.'),
        ),
      );
      return;
    }

    final scheduleData = <Map<String, dynamic>>[];

    for (final entry in schedules) {
      final start = _minutes(entry.startTime);
      final end = _minutes(entry.endTime);

      if (end <= start) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${entry.dayOfWeek}: End time must be later than start time.',
            ),
          ),
        );
        return;
      }

      scheduleData.add({
        'dayOfWeek': entry.dayOfWeek,
        'startTimeMinutes': start,
        'endTimeMinutes': end,
        'roomName': entry.roomName,
      });
    }

    // Prevent overlapping schedule entries within this same class.
    for (var i = 0; i < scheduleData.length; i++) {
      for (var j = i + 1; j < scheduleData.length; j++) {
        final first = scheduleData[i];
        final second = scheduleData[j];

        if (first['dayOfWeek'] != second['dayOfWeek']) continue;

        final firstStart = first['startTimeMinutes'] as int;
        final firstEnd = first['endTimeMinutes'] as int;
        final secondStart = second['startTimeMinutes'] as int;
        final secondEnd = second['endTimeMinutes'] as int;

        if (firstStart < secondEnd && firstEnd > secondStart) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Two schedules in this class overlap on '
                '${first['dayOfWeek']}.',
              ),
            ),
          );
          return;
        }
      }
    }

    Navigator.pop(context, {
      'subjectName': name,
      'subjectCode': code,
      'shift': selectedShift!,
      'schedules': scheduleData,
      'teacherId': selectedTeacherId,
      'teacherName': selectedTeacherName,
    });
  }

  Widget _buildScheduleCard(int index) {
    final entry = schedules[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Schedule ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove schedule',
                  onPressed: () {
                    setState(() => schedules.removeAt(index));
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: entry.dayOfWeek,
              decoration: const InputDecoration(
                labelText: 'Day',
                border: OutlineInputBorder(),
              ),
              items: days.map((day) {
                return DropdownMenuItem(value: day, child: Text(day));
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => entry.dayOfWeek = value);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(entry, isStart: true),
                    icon: const Icon(Icons.access_time),
                    label: Text('Start: ${_formatTime(entry.startTime)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(entry, isStart: false),
                    icon: const Icon(Icons.access_time),
                    label: Text('End: ${_formatTime(entry.endTime)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: entry.roomName,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Room',
                border: OutlineInputBorder(),
              ),
              items: campusLocations.map((room) {
                return DropdownMenuItem(value: room, child: Text(room));
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => entry.roomName = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Class' : 'Create Class'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectNameController,
                decoration: const InputDecoration(
                  labelText: 'Subject Name',
                  hintText: 'Example: IT Programming',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectCodeController,
                decoration: const InputDecoration(
                  labelText: 'Subject Code',
                  hintText: 'Example: IT101',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedShift,
                decoration: const InputDecoration(
                  labelText: 'Shift',
                  border: OutlineInputBorder(),
                ),
                items: shifts.map((shift) {
                  return DropdownMenuItem(value: shift, child: Text(shift));
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedShift = value);
                },
              ),
              const SizedBox(height: 12),

              if (isLoadingTeachers)
                const Center(child: CircularProgressIndicator())
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showTeacherSearch,
                    icon: const Icon(Icons.person_search),
                    label: Text(
                      selectedTeacherName ?? 'Search and Assign Teacher',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              if (selectedTeacherId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        selectedTeacherId = null;
                        selectedTeacherName = null;
                      });
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Remove assigned teacher'),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Class Schedules',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addSchedule,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Day'),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add each weekly meeting day, time, and room.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 10),
              if (schedules.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No schedules added yet.'),
                ),
              ...List.generate(
                schedules.length,
                (index) => _buildScheduleCard(index),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.isEditing ? 'Save Changes' : 'Create Class'),
        ),
      ],
    );
  }
}

class _ClassScheduleEntry {
  String dayOfWeek;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String roomName;

  _ClassScheduleEntry({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.roomName,
  });
}
