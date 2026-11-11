import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ============================================================
// CLUBS PAGE
// ============================================================

class ClubsPage extends StatelessWidget {
  const ClubsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in first.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, roleSnapshot) {
        if (roleSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load user role.')),
          );
        }

        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = roleSnapshot.data?.data()?['role'];

        if (role != 'admin' && role != 'club_advisor' && role != 'student') {
          return const Scaffold(
            body: Center(child: Text('Your account has no valid role.')),
          );
        }

        return buildClubsPage(context, user.uid, role);
      },
    );
  }

  Widget buildClubsPage(BuildContext context, String userId, String role) {
    final isAdmin = role == 'admin';
    final canCreate = isAdmin || role == 'club_advisor';

    final clubsCollection = FirebaseFirestore.instance.collection('clubs');

    final Query<Map<String, dynamic>> query;

    if (isAdmin) {
      query = clubsCollection;
    } else if (role == 'club_advisor') {
      query = clubsCollection.where('advisorId', isEqualTo: userId);
    } else {
      query = clubsCollection.where('status', isEqualTo: 'approved');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Campus Clubs'), centerTitle: true),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (dialogContext) => ClubFormDialog(isAdmin: isAdmin),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong loading clubs.'),
            );
          }

          final clubs = snapshot.data?.docs ?? [];

          if (clubs.isEmpty) {
            return const Center(child: Text('No clubs available yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Explore Clubs',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...clubs.map((club) {
                return clubCard(context, club.id, club.data(), userId, role);
              }),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // CLUB CARD
  // ============================================================

  Widget clubCard(
    BuildContext context,
    String clubId,
    Map<String, dynamic> data,
    String userId,
    String role,
  ) {
    final name = data['name'] ?? 'Untitled Club';
    final description = data['description'] ?? 'No description available.';
    final category = data['category'] ?? 'Other';
    final status = data['status'] ?? 'pending';
    final advisorId = data['advisorId'] ?? '';
    final advisorEmail = data['advisorEmail'] ?? '';

    final isAdmin = role == 'admin';
    final isAdvisor = role == 'club_advisor';
    final isStudent = role == 'student';

    final advisorOwnsClub = isAdvisor && advisorId == userId;
    final canManageClub = isAdmin || advisorOwnsClub;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: status == 'approved'
            ? () {
                if (canManageClub) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MembershipManagementPage(
                        clubId: clubId,
                        clubName: name.toString(),
                      ),
                    ),
                  );
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups, size: 35, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name.toString(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (canManageClub)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          showDialog(
                            context: context,
                            builder: (dialogContext) => ClubFormDialog(
                              isAdmin: isAdmin,
                              clubId: clubId,
                              clubData: data,
                            ),
                          );
                        } else if (value == 'delete') {
                          deleteClub(context, clubId, name.toString());
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.blue),
                              SizedBox(width: 10),
                              Text('Edit Club'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 10),
                              Text('Delete Club'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Category: $category'),
              const SizedBox(height: 6),
              Text(description.toString()),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                Text(
                  'Assigned Advisor: ${advisorEmail.toString().isEmpty ? 'Unassigned' : advisorEmail}',
                  style: const TextStyle(
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Status: ${status.toString().toUpperCase()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: status == 'approved'
                      ? Colors.green
                      : status == 'rejected'
                      ? Colors.red
                      : Colors.orange,
                ),
              ),
              if (isAdmin && status == 'pending') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            updateClubStatus(context, clubId, 'approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            updateClubStatus(context, clubId, 'rejected'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
              if (isStudent && status == 'approved') ...[
                const SizedBox(height: 10),
                membershipButton(clubId, userId),
              ],
              if (canManageClub && status == 'approved') ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.people_outline, size: 18, color: Colors.blue),
                    SizedBox(width: 5),
                    Text(
                      'Tap to manage club members',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ],
                ),
              ],

              if (advisorOwnsClub && status == 'approved') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => ClubActivityFormDialog(
                          clubId: clubId,
                          clubName: name.toString(),
                          advisorId: userId,
                        ),
                      );
                    },
                    icon: const Icon(Icons.event),
                    label: const Text('Create Club Activity'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // STUDENT MEMBERSHIP BUTTON
  // ============================================================

  Widget membershipButton(String clubId, String userId) {
    final firestore = FirebaseFirestore.instance;

    final requestRef = firestore
        .collection('club_membership_requests')
        .doc('${clubId}_$userId');

    final membershipRef = firestore
        .collection('student_memberships')
        .doc(userId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: requestRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return const Text(
            'Unable to check membership status.',
            style: TextStyle(color: Colors.red),
          );
        }

        final request = snapshot.data?.data();
        final status = request?['status'];
        final attemptCount = (request?['attemptCount'] as num?)?.toInt() ?? 0;

        if (status == 'pending') {
          return const Text(
            'Membership request pending',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          );
        }

        if (status == 'approved') {
          return const Text(
            'You are a member of this club.',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          );
        }

        if (status == 'already_member') {
          return const Text(
            'Already a member of another club.',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          );
        }

        if (status == 'removed') {
          return const Text(
            'You were removed from this club.',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          );
        }

        if (status == 'rejected' && attemptCount >= 3) {
          return const Text(
            'Maximum request attempts reached.',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final membershipSnapshot = await membershipRef.get();

                int initialPendingCount = 0;
                String? initialApprovedClubId;

                if (!membershipSnapshot.exists) {
                  final existingRequests = await firestore
                      .collection('club_membership_requests')
                      .where('studentId', isEqualTo: userId)
                      .get();

                  for (final doc in existingRequests.docs) {
                    final data = doc.data();

                    if (data['status'] == 'pending') {
                      initialPendingCount++;
                    }

                    if (data['status'] == 'approved') {
                      initialApprovedClubId = data['clubId'];
                    }
                  }
                }

                await firestore.runTransaction((transaction) async {
                  final membershipDoc = await transaction.get(membershipRef);
                  final requestDoc = await transaction.get(requestRef);

                  final membershipData = membershipDoc.data();

                  int pendingCount = initialPendingCount;
                  String? approvedClubId = initialApprovedClubId;

                  if (membershipDoc.exists) {
                    pendingCount =
                        (membershipData?['pendingCount'] as num?)?.toInt() ?? 0;
                    approvedClubId =
                        membershipData?['approvedClubId'] as String?;
                  }

                  if (approvedClubId != null && approvedClubId.isNotEmpty) {
                    throw Exception(
                      'You are already a member of another club.',
                    );
                  }

                  if (pendingCount >= 3) {
                    throw Exception(
                      'You can only have 3 pending requests at a time.',
                    );
                  }

                  final existingData = requestDoc.data();
                  final existingStatus = existingData?['status'];

                  int currentAttempts =
                      (existingData?['attemptCount'] as num?)?.toInt() ?? 0;

                  if (requestDoc.exists &&
                      existingStatus != 'rejected' &&
                      existingStatus != 'available') {
                    throw Exception(
                      'This membership request cannot be submitted again.',
                    );
                  }

                  if (requestDoc.exists &&
                      existingStatus == 'rejected' &&
                      currentAttempts == 0) {
                    currentAttempts = 1;
                  }

                  if (!requestDoc.exists || existingStatus == 'rejected') {
                    if (currentAttempts >= 3) {
                      throw Exception(
                        'You have reached the maximum of 3 attempts.',
                      );
                    }
                    currentAttempts++;
                  }

                  transaction.set(membershipRef, {
                    'pendingCount': pendingCount + 1,
                    'approvedClubId': null,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));

                  transaction.set(requestRef, {
                    'clubId': clubId,
                    'studentId': userId,
                    'status': 'pending',
                    'attemptCount': currentAttempts,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                });

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Membership request submitted!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (error) {
                if (!context.mounted) return;

                final message = error.toString().replaceFirst(
                  'Exception: ',
                  '',
                );

                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
              }
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Request to Join'),
          ),
        );
      },
    );
  }

  // ============================================================
  // MEMBERSHIP REQUESTS SECTION
  // ============================================================

  Widget membershipRequestsSection(BuildContext context, String clubId) {
    final requestsQuery = FirebaseFirestore.instance
        .collection('club_membership_requests')
        .where('clubId', isEqualTo: clubId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: requestsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return const Text(
            'Unable to load membership requests.',
            style: TextStyle(color: Colors.red),
          );
        }

        final allRequests = snapshot.data?.docs ?? [];

        final visibleRequests = allRequests.where((request) {
          final status = request.data()['status'];

          return status == 'pending' ||
              status == 'approved' ||
              status == 'rejected';
        }).toList();

        if (visibleRequests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('No membership records yet.')),
          );
        }

        // Fetch student information once for this snapshot.
        final studentsFuture = Future.wait(
          visibleRequests.map((request) async {
            final studentId = request.data()['studentId']?.toString() ?? '';

            final studentSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(studentId)
                .get();

            final studentName =
                studentSnapshot.data()?['name']?.toString() ??
                'Unknown Student';

            return <String, dynamic>{
              'request': request,
              'studentId': studentId,
              'studentName': studentName,
              'status': request.data()['status']?.toString() ?? '',
            };
          }),
        );

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: studentsFuture,
          builder: (context, studentSnapshot) {
            if (studentSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (studentSnapshot.hasError) {
              return const Text(
                'Unable to load student information.',
                style: TextStyle(color: Colors.red),
              );
            }

            final students = studentSnapshot.data ?? [];

            return _MembershipSearchTable(
              key: ValueKey(clubId),
              students: students,
              updateMembershipStatus: updateMembershipStatus,
              parentContext: context,
            );
          },
        );
      },
    );
  }

  // ============================================================
  // UPDATE MEMBERSHIP STATUS
  // ============================================================

  Future<void> updateMembershipStatus(
    BuildContext context,
    String requestId,
    String status,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;

      final requestRef = firestore
          .collection('club_membership_requests')
          .doc(requestId);

      final requestSnapshot = await requestRef.get();

      if (!requestSnapshot.exists) {
        throw Exception('Membership request not found.');
      }

      final requestData = requestSnapshot.data()!;
      final studentId = requestData['studentId'] as String;
      final clubId = requestData['clubId'] as String;
      final currentStatus = requestData['status'];

      if (status == 'approved' || status == 'rejected') {
        if (currentStatus != 'pending') {
          throw Exception('This request is no longer pending.');
        }
      } else if (status == 'removed') {
        if (currentStatus != 'approved') {
          throw Exception('This student is not an approved member.');
        }
      } else {
        throw Exception('Invalid membership status.');
      }

      final membershipRef = firestore
          .collection('student_memberships')
          .doc(studentId);

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw Exception('User is not logged in.');
      }

      final userDoc = await firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final isAdminUser = userDoc.data()?['role'] == 'admin';

      List<DocumentReference<Map<String, dynamic>>> relatedRefs = [];

      if (isAdminUser && (status == 'approved' || status == 'removed')) {
        final relatedStatus = status == 'approved'
            ? 'pending'
            : 'already_member';

        final relatedRequests = await firestore
            .collection('club_membership_requests')
            .where('studentId', isEqualTo: studentId)
            .where('status', isEqualTo: relatedStatus)
            .get();

        relatedRefs = relatedRequests.docs
            .where((doc) => doc.id != requestId)
            .map((doc) => doc.reference)
            .toList();
      }

      await firestore.runTransaction((transaction) async {
        final currentRequest = await transaction.get(requestRef);
        final membershipDoc = await transaction.get(membershipRef);

        final relatedSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];

        for (final ref in relatedRefs) {
          relatedSnapshots.add(await transaction.get(ref));
        }

        if (!currentRequest.exists ||
            currentRequest.data()?['status'] != currentStatus) {
          throw Exception('The membership status has changed. Please retry.');
        }

        final membershipData = membershipDoc.data();

        final approvedClubId = membershipData?['approvedClubId'] as String?;

        int pendingCount =
            (membershipData?['pendingCount'] as num?)?.toInt() ?? 0;

        if (status == 'approved') {
          if (approvedClubId != null &&
              approvedClubId.isNotEmpty &&
              approvedClubId != clubId) {
            throw Exception(
              'This student is already a member of another club.',
            );
          }

          transaction.update(requestRef, {'status': 'approved'});

          for (final related in relatedSnapshots) {
            if (related.exists && related.data()?['status'] == 'pending') {
              transaction.update(related.reference, {
                'status': 'already_member',
              });
            }
          }

          transaction.set(membershipRef, {
            'pendingCount': 0,
            'approvedClubId': clubId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (status == 'rejected') {
          transaction.update(requestRef, {'status': 'rejected'});

          pendingCount = pendingCount > 0 ? pendingCount - 1 : 0;

          transaction.set(membershipRef, {
            'pendingCount': pendingCount,
            'approvedClubId': approvedClubId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (status == 'removed') {
          transaction.update(requestRef, {'status': 'removed'});

          for (final related in relatedSnapshots) {
            if (related.exists &&
                related.data()?['status'] == 'already_member') {
              transaction.update(related.reference, {'status': 'available'});
            }
          }

          transaction.set(membershipRef, {
            'pendingCount': 0,
            'approvedClubId': null,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      if (!context.mounted) return;

      final message = status == 'approved'
          ? 'Student membership approved!'
          : status == 'rejected'
          ? 'Student membership rejected.'
          : 'Student successfully removed from the club.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: status == 'rejected' ? Colors.orange : Colors.green,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      final message = error.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update membership: $message')),
      );
    }
  }

  // ============================================================
  // UPDATE CLUB STATUS
  // ============================================================

  Future<void> updateClubStatus(
    BuildContext context,
    String clubId,
    String status,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('clubs').doc(clubId).update({
        'status': status,
      });

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Club approved successfully!'
                : 'Club rejected.',
          ),
          backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update club: $error')));
    }
  }

  // ============================================================
  // DELETE CLUB
  // ============================================================

  Future<void> deleteClub(
    BuildContext context,
    String clubId,
    String name,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Club?'),
        content: Text(
          'Are you sure you want to delete "$name"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('clubs').doc(clubId).delete();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Club deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete club: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ============================================================
// SEARCHABLE MEMBERSHIP TABLE
// This is now OUTSIDE ClubsPage.
// ============================================================

class _MembershipSearchTable extends StatefulWidget {
  final List<Map<String, dynamic>> students;

  final Future<void> Function(BuildContext, String, String)
  updateMembershipStatus;

  final BuildContext parentContext;

  const _MembershipSearchTable({
    super.key,
    required this.students,
    required this.updateMembershipStatus,
    required this.parentContext,
  });

  @override
  State<_MembershipSearchTable> createState() => _MembershipSearchTableState();
}

class _MembershipSearchTableState extends State<_MembershipSearchTable> {
  String searchQuery = '';
  String selectedStatus = 'all';

  @override
  Widget build(BuildContext context) {
    // Summary counts are based on all loaded membership records.
    final pendingCount = widget.students
        .where((student) => student['status'] == 'pending')
        .length;

    final approvedCount = widget.students
        .where((student) => student['status'] == 'approved')
        .length;

    final rejectedCount = widget.students
        .where((student) => student['status'] == 'rejected')
        .length;

    // Apply both search and status filters.
    final filteredStudents = widget.students.where((student) {
      final name = student['studentName'].toString().toLowerCase();
      final id = student['studentId'].toString().toLowerCase();
      final status = student['status'].toString().toLowerCase();

      final matchesSearch =
          name.contains(searchQuery) || id.contains(searchQuery);

      final matchesStatus = selectedStatus == 'all' || status == selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();

    Widget summaryCard(String title, int count, Color color) {
      return SizedBox(
        width: 105,
        child: Card(
          color: color.withValues(alpha: 0.10),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MEMBERSHIP SUMMARY CARDS
        const Text(
          'Membership Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            summaryCard('Pending', pendingCount, Colors.orange),
            summaryCard('Approved', approvedCount, Colors.green),
            summaryCard('Rejected', rejectedCount, Colors.red),
          ],
        ),

        const SizedBox(height: 20),

        // SEARCH FIELD
        TextField(
          onChanged: (value) {
            setState(() {
              searchQuery = value.toLowerCase().trim();
            });
          },
          decoration: InputDecoration(
            hintText: 'Search student name or ID...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // STATUS FILTERS
        const Text(
          'Filter by Status',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: selectedStatus == 'all',
              onSelected: (_) {
                setState(() => selectedStatus = 'all');
              },
            ),
            ChoiceChip(
              label: const Text('Pending'),
              selected: selectedStatus == 'pending',
              selectedColor: Colors.orange.shade100,
              onSelected: (_) {
                setState(() => selectedStatus = 'pending');
              },
            ),
            ChoiceChip(
              label: const Text('Approved'),
              selected: selectedStatus == 'approved',
              selectedColor: Colors.green.shade100,
              onSelected: (_) {
                setState(() => selectedStatus = 'approved');
              },
            ),
            ChoiceChip(
              label: const Text('Rejected'),
              selected: selectedStatus == 'rejected',
              selectedColor: Colors.red.shade100,
              onSelected: (_) {
                setState(() => selectedStatus = 'rejected');
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // STUDENT TABLE
        Text(
          'Students (${filteredStudents.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        if (filteredStudents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('No matching students found.')),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
              columnSpacing: 24,
              horizontalMargin: 12,
              columns: const [
                DataColumn(label: Text('Student Name')),
                DataColumn(label: Text('Student ID')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: filteredStudents.map((student) {
                final request =
                    student['request']
                        as QueryDocumentSnapshot<Map<String, dynamic>>;

                final studentName = student['studentName'].toString();
                final studentId = student['studentId'].toString();
                final status = student['status'].toString();

                final statusColor = status == 'pending'
                    ? Colors.orange
                    : status == 'approved'
                    ? Colors.green
                    : Colors.red;

                final statusBadge = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                );

                Widget actions;

                if (status == 'pending') {
                  actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => widget.updateMembershipStatus(
                          widget.parentContext,
                          request.id,
                          'approved',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Approve'),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => widget.updateMembershipStatus(
                          widget.parentContext,
                          request.id,
                          'rejected',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Reject'),
                      ),
                    ],
                  );
                } else if (status == 'approved') {
                  actions = ElevatedButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: widget.parentContext,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Remove Student'),
                          content: const Text(
                            'Are you sure you want to remove this student '
                            'from the club?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await widget.updateMembershipStatus(
                          widget.parentContext,
                          request.id,
                          'removed',
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Remove'),
                  );
                } else {
                  actions = const Text(
                    'No action',
                    style: TextStyle(color: Colors.grey),
                  );
                }

                return DataRow(
                  cells: [
                    DataCell(Text(studentName)),
                    DataCell(Text(studentId)),
                    DataCell(statusBadge),
                    DataCell(actions),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// CLUB FORM DIALOG
// ============================================================

class ClubFormDialog extends StatefulWidget {
  final String? clubId;
  final Map<String, dynamic>? clubData;
  final bool isAdmin;

  const ClubFormDialog({
    super.key,
    this.clubId,
    this.clubData,
    this.isAdmin = false,
  });

  @override
  State<ClubFormDialog> createState() => _ClubFormDialogState();
}

class _ClubFormDialogState extends State<ClubFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final categoryController = TextEditingController();

  bool isSaving = false;

  String selectedAdvisorId = '';
  String selectedAdvisorEmail = '';

  bool get isEditing => widget.clubId != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      final data = widget.clubData!;

      nameController.text = data['name'] ?? '';
      descriptionController.text = data['description'] ?? '';
      categoryController.text = data['category'] ?? '';

      selectedAdvisorId = data['advisorId'] ?? '';
      selectedAdvisorEmail = data['advisorEmail'] ?? '';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
    super.dispose();
  }

  Widget buildAdvisorDropdown() {
    final advisorsQuery = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'club_advisor');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: advisorsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return const Text(
            'Unable to load Club Advisors.',
            style: TextStyle(color: Colors.red),
          );
        }

        final advisors = snapshot.data?.docs ?? [];
        final advisorIds = advisors.map((doc) => doc.id).toSet();

        return DropdownButtonFormField<String>(
          value: selectedAdvisorId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Assign Club Advisor',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Unassigned'),
            ),
            ...advisors.map((advisor) {
              final email =
                  advisor.data()['email'] ??
                  advisor.data()['name'] ??
                  advisor.id;

              return DropdownMenuItem<String>(
                value: advisor.id,
                child: Text(email.toString(), overflow: TextOverflow.ellipsis),
              );
            }),
            if (selectedAdvisorId.isNotEmpty &&
                !advisorIds.contains(selectedAdvisorId))
              DropdownMenuItem<String>(
                value: selectedAdvisorId,
                child: Text(
                  selectedAdvisorEmail.isNotEmpty
                      ? 'Current assignment: $selectedAdvisorEmail'
                      : 'Current assignment',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              selectedAdvisorId = value;

              if (value.isEmpty) {
                selectedAdvisorEmail = '';
              } else {
                final matchingAdvisors = advisors.where(
                  (advisor) => advisor.id == value,
                );

                if (matchingAdvisors.isNotEmpty) {
                  final advisorData = matchingAdvisors.first.data();

                  selectedAdvisorEmail =
                      advisorData['email'] ?? advisorData['name'] ?? '';
                }
              }
            });
          },
        );
      },
    );
  }

  Widget buildCategoryDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('club_categories')
          .orderBy(FieldPath.documentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return const Text(
            'Unable to load club categories.',
            style: TextStyle(color: Colors.red),
          );
        }

        final categories = snapshot.data?.docs ?? [];

        final categoryNames = categories
            .map((doc) => doc.data()['name'].toString())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();

        final currentCategory = categoryController.text.trim();

        if (currentCategory.isNotEmpty &&
            !categoryNames.contains(currentCategory)) {
          categoryNames.add(currentCategory);
        }

        return DropdownButtonFormField<String>(
          value: currentCategory.isEmpty ? null : currentCategory,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Club Category',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.category),
          ),
          hint: const Text('Select a category'),
          items: categoryNames.map((category) {
            return DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              categoryController.text = value;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a category';
            }
            return null;
          },
        );
      },
    );
  }

  Future<void> saveClub() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      isSaving = true;
    });

    final enteredName = nameController.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    final normalizedClubName = enteredName.toLowerCase();

    final clubData = {
      'name': enteredName,
      'description': descriptionController.text.trim(),
      'category': categoryController.text.trim(),
    };

    try {
      final existingClubs = await FirebaseFirestore.instance
          .collection('clubs')
          .get();

      final isDuplicate = existingClubs.docs.any((doc) {
        if (isEditing && doc.id == widget.clubId) {
          return false;
        }

        final existingName = (doc.data()['name'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();

        return existingName == normalizedClubName;
      });

      if (isDuplicate) {
        if (!mounted) return;

        setState(() {
          isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A club with this name already exists!'),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      if (isEditing) {
        final updateData = <String, dynamic>{...clubData};

        if (widget.isAdmin) {
          updateData['advisorId'] = selectedAdvisorId;
          updateData['advisorEmail'] = selectedAdvisorEmail;
        }

        await FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.clubId)
            .update(updateData);
      } else {
        final advisorId = widget.isAdmin ? selectedAdvisorId : user.uid;

        final advisorEmail = widget.isAdmin
            ? selectedAdvisorEmail
            : user.email ?? '';

        await FirebaseFirestore.instance.collection('clubs').add({
          ...clubData,
          'advisorId': advisorId,
          'advisorEmail': advisorEmail,
          'status': widget.isAdmin ? 'approved' : 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Club updated successfully!'
                : widget.isAdmin
                ? 'Club created and approved successfully!'
                : 'Club submitted for admin approval!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save club: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(isEditing ? 'Edit Club' : 'Create New Club'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Club Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.groups),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a club name';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            buildCategoryDropdown(),
            const SizedBox(height: 14),
            TextFormField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            if (widget.isAdmin) ...[
              const SizedBox(height: 14),
              buildAdvisorDropdown(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : saveClub,
          child: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update Club' : 'Submit Club'),
        ),
      ],
    );
  }
}

// ============================================================
// MEMBERSHIP MANAGEMENT PAGE
// ============================================================

class MembershipManagementPage extends StatelessWidget {
  final String clubId;
  final String clubName;

  const MembershipManagementPage({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(clubName),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Club Membership Management',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClubsPage().membershipRequestsSection(context, clubId),
          ],
        ),
      ),
    );
  }
}

class ClubActivityFormDialog extends StatefulWidget {
  final String clubId;
  final String clubName;
  final String advisorId;

  const ClubActivityFormDialog({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.advisorId,
  });

  @override
  State<ClubActivityFormDialog> createState() => _ClubActivityFormDialogState();
}

class _ClubActivityFormDialogState extends State<ClubActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  String? selectedRoom;
  bool isSaving = false;

  final List<String> rooms = [
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

  int _toMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (startTime ?? TimeOfDay.now())
          : (endTime ?? TimeOfDay.now()),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          startTime = picked;
        } else {
          endTime = picked;
        }
      });
    }
  }

  Future<void> _submitActivity() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedDate == null ||
        startTime == null ||
        endTime == null ||
        selectedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the date, time, and room fields.'),
        ),
      );
      return;
    }

    final start = _toMinutes(startTime!);
    final end = _toMinutes(endTime!);

    if (end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be later than start time.'),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('club_activities').add({
        'clubId': widget.clubId,
        'clubName': widget.clubName,
        'activityTitle': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'advisorId': widget.advisorId,
        'roomName': selectedRoom,
        'date': Timestamp.fromDate(
          DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day),
        ),
        'startTimeMinutes': start,
        'endTimeMinutes': end,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Club activity submitted for admin approval!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit activity: $error')),
      );
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Create Club Activity'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.clubName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Activity Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an activity title'
                  : null,
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an activity description'
                  : null,
            ),

            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              initialValue: selectedRoom,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Requested Room',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.meeting_room),
              ),
              items: rooms.map((room) {
                return DropdownMenuItem(value: room, child: Text(room));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedRoom = value);
              },
              validator: (value) => value == null ? 'Select a room' : null,
            ),

            const SizedBox(height: 14),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month),
              title: const Text('Activity Date'),
              subtitle: Text(
                selectedDate == null
                    ? 'Select date'
                    : MaterialLocalizations.of(context)
                          .formatMediumDate(selectedDate!),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickDate,
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('Start Time'),
              subtitle: Text(
                startTime == null
                    ? 'Select start time'
                    : startTime!.format(context),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _pickTime(true),
            ),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_filled),
              title: const Text('End Time'),
              subtitle: Text(
                endTime == null ? 'Select end time' : endTime!.format(context),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _pickTime(false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : _submitActivity,
          child: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit Request'),
        ),
      ],
    );
  }
}

class ClubActivityApprovalPage extends StatefulWidget {
  const ClubActivityApprovalPage({super.key});

  @override
  State<ClubActivityApprovalPage> createState() =>
      _ClubActivityApprovalPageState();
}

class _ClubActivityApprovalPageState extends State<ClubActivityApprovalPage> {
  String selectedFilter = 'pending';

  String formatTime(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

    return time.format(context);
  }

  Future<void> updateActivityStatus(String activityId, String status) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          status == 'approved' ? 'Approve Activity?' : 'Reject Activity?',
        ),
        content: Text(
          status == 'approved'
              ? 'Are you sure you want to approve this club activity?'
              : 'Are you sure you want to reject this club activity?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'approved' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(status == 'approved' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Please log in first.');
      }

      await FirebaseFirestore.instance
          .collection('club_activities')
          .doc(activityId)
          .update({
            'status': status,
            'reviewedBy': user.uid,
            'reviewedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Club activity approved!'
                : 'Club activity rejected.',
          ),
          backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update activity: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget activityCard(String activityId, Map<String, dynamic> data) {
    final title = data['activityTitle'] ?? 'Untitled Activity';
    final clubName = data['clubName'] ?? 'Unknown Club';
    final description = data['description'] ?? '';
    final room = data['roomName'] ?? 'No room selected';
    final status = data['status'] ?? 'pending';

    final dateValue = data['date'];
    final date = dateValue is Timestamp ? dateValue.toDate() : DateTime.now();

    final start = (data['startTimeMinutes'] as num?)?.toInt() ?? 0;
    final end = (data['endTimeMinutes'] as num?)?.toInt() ?? 0;

    final statusColor = status == 'approved'
        ? Colors.green
        : status == 'rejected'
        ? Colors.red
        : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, color: Colors.blue, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title.toString(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              'Club: $clubName',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 6),
            Text(description.toString()),

            const Divider(height: 24),

            Row(
              children: [
                const Icon(Icons.meeting_room_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Requested room: $room')),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.calendar_month, size: 18),
                const SizedBox(width: 8),
                Text(MaterialLocalizations.of(context).formatMediumDate(date)),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.access_time, size: 18),
                const SizedBox(width: 8),
                Text('${formatTime(start)} - ${formatTime(end)}'),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Text('Status: '),
                Text(
                  status.toString().toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            if (status == 'pending') ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          updateActivityStatus(activityId, 'approved'),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          updateActivityStatus(activityId, 'rejected'),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in first.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (roleSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to verify admin access.')),
          );
        }

        final role = roleSnapshot.data?.data()?['role'];

        if (role != 'admin') {
          return const Scaffold(
            body: Center(
              child: Text('Only administrators can access this page.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Club Activity Requests'),
            centerTitle: true,
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('club_activities')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load club activities.'),
                );
              }

              final activities = snapshot.data?.docs ?? [];

              final filteredActivities = activities.where((activity) {
                final status = activity.data()['status'] ?? 'pending';

                return selectedFilter == 'all' || status == selectedFilter;
              }).toList();

              filteredActivities.sort((a, b) {
                final aDate = a.data()['createdAt'];
                final bDate = b.data()['createdAt'];

                final aTime = aDate is Timestamp
                    ? aDate.millisecondsSinceEpoch
                    : 0;

                final bTime = bDate is Timestamp
                    ? bDate.millisecondsSinceEpoch
                    : 0;

                return bTime.compareTo(aTime);
              });

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _filterChip('Pending', 'pending'),
                        _filterChip('Approved', 'approved'),
                        _filterChip('Rejected', 'rejected'),
                        _filterChip('All', 'all'),
                      ],
                    ),
                  ),

                  Expanded(
                    child: filteredActivities.isEmpty
                        ? const Center(
                            child: Text('No activity requests found.'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredActivities.length,
                            itemBuilder: (context, index) {
                              final activity = filteredActivities[index];

                              return activityCard(activity.id, activity.data());
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: selectedFilter == value,
      onSelected: (_) {
        setState(() {
          selectedFilter = value;
        });
      },
    );
  }
}
