import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';

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

        if (role != 'admin' && role != 'teacher' && role != 'student') {
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
    final canCreate = isAdmin || role == 'teacher';

    final clubsCollection = FirebaseFirestore.instance.collection('clubs');
    String searchQuery = '';

    final Query<Map<String, dynamic>> query;

    if (isAdmin) {
      query = clubsCollection;
    } else if (role == 'teacher') {
      query = clubsCollection.where('advisorId', isEqualTo: userId);
    } else {
      query = clubsCollection.where('status', isEqualTo: 'approved');
    }

    final clubsStream = query.snapshots();

    return StatefulBuilder(
      builder: (context, setSearchState) {
        return Scaffold(
          appBar: AppBar(title: const Text('Campus Clubs'), centerTitle: true),
          floatingActionButton: canCreate
              ? FloatingActionButton(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) =>
                          ClubFormDialog(isAdmin: isAdmin),
                    );
                  },
                  child: const Icon(Icons.add),
                )
              : null,
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: clubsStream,
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

              final filteredClubs = clubs.where((club) {
                final name = (club.data()['name'] ?? '')
                    .toString()
                    .toLowerCase();

                return name.contains(searchQuery.trim().toLowerCase());
              }).toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Explore Clubs',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // SEARCH BAR
                  TextField(
                    onChanged: (value) {
                      setSearchState(() {
                        searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search clubs...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setSearchState(() {
                                  searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (role == 'student') ...[
                    _membershipAttemptsSummary(userId),
                    const SizedBox(height: 16),
                  ],

                  if (filteredClubs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No clubs match your search.')),
                    )
                  else
                    ...filteredClubs.map((club) {
                      return clubCard(
                        context,
                        club.id,
                        club.data(),
                        userId,
                        role,
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
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
    final isAdvisor = role == 'teacher';
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdvisorClubActivityRequestsPage(
                            advisorId: userId,
                            clubId: clubId,
                            clubName: name.toString(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('View My Activity Requests'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _membershipAttemptsSummary(String userId) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('club_membership_requests')
          .where('studentId', isEqualTo: userId)
          .snapshots(),
      builder: (context, requestsSnapshot) {
        if (requestsSnapshot.hasError) {
          return const SizedBox.shrink();
        }

        if (!requestsSnapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final requests = requestsSnapshot.data!.docs;

        final attemptsUsed = requests.fold<int>(0, (total, doc) {
          final data = doc.data();

          // Cancelled requests should not count toward the blue bars.
          if (data['status'] == 'available') {
            return total;
          }

          final count = (data['attemptCount'] as num?)?.toInt() ?? 1;

          return total + count;
        });

        final hasApprovedRequest = requests.any(
          (doc) => doc.data()['status'] == 'approved',
        );

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('student_memberships')
              .doc(userId)
              .snapshots(),
          builder: (context, membershipSnapshot) {
            if (membershipSnapshot.hasError) {
              return const SizedBox.shrink();
            }

            if (!membershipSnapshot.hasData) {
              return const LinearProgressIndicator();
            }

            final membershipData = membershipSnapshot.data!.data();
            final approvedClubId = membershipData?['approvedClubId'] as String?;

            if (hasApprovedRequest ||
                (approvedClubId != null && approvedClubId.isNotEmpty)) {
              return const SizedBox.shrink();
            }

            return _membershipAttemptIndicator(attemptsUsed.clamp(0, 3));
          },
        );
      },
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('club_membership_requests')
          .where('studentId', isEqualTo: userId)
          .snapshots(),
      builder: (context, allRequestsSnapshot) {
        if (allRequestsSnapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (allRequestsSnapshot.hasError) {
          return const Text(
            'Unable to check membership attempts.',
            style: TextStyle(color: Colors.red),
          );
        }

        final totalRequests =
            allRequestsSnapshot.data?.docs.where((doc) {
              final status = doc.data()['status'];

              return status == 'pending' || status == 'rejected';
            }).length ??
            0;

        final hasApprovedOtherClub =
            allRequestsSnapshot.data?.docs.any((doc) {
              final data = doc.data();

              return data['status'] == 'approved' && data['clubId'] != clubId;
            }) ??
            false;

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
            final attemptCount =
                (request?['attemptCount'] as num?)?.toInt() ?? 0;

            if (hasApprovedOtherClub) {
              return const Text(
                'Already a member of another club.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              );
            }

            if (status == 'pending') {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  const Text(
                    'Membership request pending',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Cancel Membership Request?'),
                            content: const Text(
                              'Are you sure you want to cancel your '
                              'pending request for this club?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Keep Request'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Yes, Cancel'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirm != true) return;

                      try {
                        await firestore.runTransaction((transaction) async {
                          final requestDoc = await transaction.get(requestRef);
                          final membershipDoc = await transaction.get(
                            membershipRef,
                          );

                          if (!requestDoc.exists ||
                              requestDoc.data()?['status'] != 'pending') {
                            throw Exception(
                              'This request is no longer pending.',
                            );
                          }

                          final membershipData = membershipDoc.data();
                          final pendingCount =
                              (membershipData?['pendingCount'] as num?)
                                  ?.toInt() ??
                              0;

                          if (!membershipDoc.exists ||
                              pendingCount < 1 ||
                              membershipData?['approvedClubId'] != null) {
                            throw Exception(
                              'Unable to update your pending request count.',
                            );
                          }

                          transaction.update(requestRef, {
                            'status': 'available',
                          });

                          transaction.update(membershipRef, {
                            'pendingCount': pendingCount - 1,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        });

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Membership request cancelled.'),
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
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel Request'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              );
            }

            if (status == 'approved') {
              return const Text(
                'You are a member of this club.',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              );
            }

            if (status == 'already_member') {
              return const Text(
                'Already a member of another club.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              );
            }

            if (status == 'removed') {
              return const Text(
                'You were removed from this club.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              );
            }

            if (totalRequests >= 3 || attemptCount >= 3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Maximum request attempts reached.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                SizedBox(
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
                          final membershipDoc = await transaction.get(
                            membershipRef,
                          );
                          final requestDoc = await transaction.get(requestRef);

                          final membershipData = membershipDoc.data();

                          int pendingCount = initialPendingCount;
                          String? approvedClubId = initialApprovedClubId;

                          if (membershipDoc.exists) {
                            pendingCount =
                                (membershipData?['pendingCount'] as num?)
                                    ?.toInt() ??
                                0;
                            approvedClubId =
                                membershipData?['approvedClubId'] as String?;
                          }

                          if (approvedClubId != null &&
                              approvedClubId.isNotEmpty) {
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
                              (existingData?['attemptCount'] as num?)
                                  ?.toInt() ??
                              0;

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

                          if (!requestDoc.exists ||
                              existingStatus == 'rejected') {
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
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _membershipAttemptIndicator(int attempts) {
    final remaining = (3 - attempts).clamp(0, 3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Membership Request Attempts',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$attempts / 3',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Container(
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: index < attempts
                        ? Colors.blue
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$remaining ${remaining == 1 ? 'attempt' : 'attempts'} remaining',
            style: TextStyle(
              color: remaining == 0 ? Colors.red : Colors.blue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

            final studentData = studentSnapshot.data();

            final studentName =
                studentData?['name']?.toString() ?? 'Unknown Student';

            final institutionalId =
                studentData?['institutionalId']?.toString() ?? 'Not available';

            return <String, dynamic>{
              'request': request,
              'studentId': studentId,
              'institutionalId': institutionalId,
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
      final isTeacherUser = userDoc.data()?['role'] == 'teacher';

      if (!isAdminUser && !isTeacherUser) {
        throw Exception('You are not authorized to manage memberships.');
      }

      List<DocumentReference<Map<String, dynamic>>> relatedRefs = [];

      if ((isAdminUser || isTeacherUser) &&
          (status == 'approved' || status == 'removed')) {
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
            'managedRequestId': requestId,
            'managedClubId': clubId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (status == 'rejected') {
          transaction.update(requestRef, {'status': 'rejected'});

          pendingCount = pendingCount > 0 ? pendingCount - 1 : 0;

          transaction.set(membershipRef, {
            'pendingCount': pendingCount,
            'approvedClubId': approvedClubId,
            'managedRequestId': requestId,
            'managedClubId': clubId,
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
            'managedRequestId': requestId,
            'managedClubId': clubId,
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

        // STUDENT CARDS
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
          ...filteredStudents.map((student) {
            final request =
                student['request']
                    as QueryDocumentSnapshot<Map<String, dynamic>>;

            final studentName = student['studentName'].toString();
            final institutionalId = student['institutionalId'].toString();
            final status = student['status'].toString();

            final statusColor = status == 'pending'
                ? Colors.orange
                : status == 'approved'
                ? Colors.green
                : Colors.red;

            final statusBadge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => widget.updateMembershipStatus(
                        widget.parentContext,
                        request.id,
                        'approved',
                      ),
                      icon: const Icon(Icons.check, size: 18),
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
                      onPressed: () => widget.updateMembershipStatus(
                        widget.parentContext,
                        request.id,
                        'rejected',
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              );
            } else if (status == 'approved') {
              actions = SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
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
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && widget.parentContext.mounted) {
                      await widget.updateMembershipStatus(
                        widget.parentContext,
                        request.id,
                        'removed',
                      );
                    }
                  },
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Remove Member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              );
            } else {
              actions = const Text(
                'No actions available for this request.',
                style: TextStyle(color: Colors.grey),
              );
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEAF2FA),
                  child: Icon(Icons.person_outline, color: Color(0xFF245A91)),
                ),
                title: Text(
                  studentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'School ID: $institutionalId',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusBadge,
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('School ID'),
                    subtitle: Text(institutionalId),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Membership Status'),
                    subtitle: Text(status.toUpperCase()),
                  ),
                  const SizedBox(height: 8),
                  actions,
                ],
              ),
            );
          }),
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
        .where('role', isEqualTo: 'teacher');

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
            'Unable to load Teachers.',
            style: TextStyle(color: Colors.red),
          );
        }

        final advisors = snapshot.data?.docs ?? [];
        final advisorIds = advisors.map((doc) => doc.id).toSet();

        return DropdownButtonFormField<String>(
          initialValue: selectedAdvisorId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Assign Teacher',
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
          initialValue: currentCategory.isEmpty ? null : currentCategory,
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

  static const int operatingStartMinutes = 8 * 60; // 8:00 AM
  static const int operatingEndMinutes = 21 * 60; // 9:00 PM

  DateTime? selectedDate;
  DateTime focusedDay = DateTime.now();

  TimeOfDay? startTime;
  TimeOfDay? endTime;

  String? selectedRoom;
  bool isSaving = false;

  Set<DateTime> unavailableDates = {};
  Set<DateTime> tentativeDates = {};
  List<Map<String, dynamic>> selectedDateBookings = [];
  List<Map<String, dynamic>> selectedDatePendingBookings = [];
  List<Map<String, int>> availableTimeRanges = [];

  bool isLoadingDateAvailability = false;

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

  String _formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;

    final time = TimeOfDay(hour: hour, minute: minute);
    return time.format(context);
  }

  void _calculateAvailableTimeRanges() {
    final bookings = [...selectedDateBookings];

    bookings.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    availableTimeRanges.clear();

    int currentStart = operatingStartMinutes;

    for (final booking in bookings) {
      final start = booking['start'] as int;
      final end = booking['end'] as int;

      if (start > currentStart) {
        availableTimeRanges.add({'start': currentStart, 'end': start});
      }

      if (end > currentStart) {
        currentStart = end;
      }
    }

    if (currentStart < operatingEndMinutes) {
      availableTimeRanges.add({
        'start': currentStart,
        'end': operatingEndMinutes,
      });
    }

    availableTimeRanges.removeWhere(
      (range) => range['end']! <= range['start']!,
    );
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _hasTimeOverlap(
    int existingStart,
    int existingEnd,
    int selectedStart,
    int selectedEnd,
  ) {
    return existingStart < selectedEnd && existingEnd > selectedStart;
  }

  Future<void> loadMonthlyAvailability(DateTime month) async {
    if (selectedRoom == null) return;

    final firestore = FirebaseFirestore.instance;

    final firstDay = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);

    final confirmed = <DateTime>{};
    final tentative = <DateTime>{};

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    try {
      // 1. Load Campus Events for this month.
      final eventsSnapshot = await firestore
          .collection('events')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .where('date', isLessThan: Timestamp.fromDate(nextMonth))
          .get();

      for (final doc in eventsSnapshot.docs) {
        final data = doc.data();

        // Campus Events use "location", not "roomName".
        if (data['location']?.toString() != selectedRoom) continue;

        final status = data['status']?.toString().toLowerCase();

        if (status == 'approved') {
          final dateValue = data['date'];

          if (dateValue is Timestamp) {
            confirmed.add(_dateOnly(dateValue.toDate()));
          }
        } else if (status == 'pending') {
          final dateValue = data['date'];

          if (dateValue is Timestamp) {
            tentative.add(_dateOnly(dateValue.toDate()));
          }
        }
      }

      // 2. Load Club Activities for this month.
      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('status', whereIn: ['approved', 'pending'])
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .where('date', isLessThan: Timestamp.fromDate(nextMonth))
          .get();

      for (final doc in activitiesSnapshot.docs) {
        final data = doc.data();

        if (data['roomName']?.toString() != selectedRoom) continue;

        final dateValue = data['date'];
        if (dateValue is! Timestamp) continue;

        final date = _dateOnly(dateValue.toDate());
        final status = data['status']?.toString().toLowerCase();

        if (status == 'approved') {
          confirmed.add(date);
        } else if (status == 'pending') {
          tentative.add(date);
        }
      }

      // 3. Load active class schedules for this room.
      final classesSnapshot = await firestore
          .collection('classes')
          .where('status', isEqualTo: 'active')
          .get();
      debugPrint('========== CALENDAR AVAILABILITY DEBUG ==========');
      debugPrint('Selected room: $selectedRoom');
      debugPrint('Active classes found: ${classesSnapshot.docs.length}');

      final occupiedWeekdays = <String>{};

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final schedules = classData['schedules'];
        debugPrint('Class: ${classData['subjectName']}');
        debugPrint('Schedules: $schedules');

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;

          if (schedule['roomName']?.toString() != selectedRoom) {
            continue;
          }

          final day = schedule['dayOfWeek']?.toString();

          if (weekdays.contains(day)) {
            occupiedWeekdays.add(day!);
          }
        }
      }
      debugPrint('Occupied weekdays: $occupiedWeekdays');
      debugPrint('=================================================');

      // Mark every matching weekday in this month.
      for (
        DateTime date = firstDay;
        date.isBefore(nextMonth);
        date = date.add(const Duration(days: 1))
      ) {
        final day = weekdays[date.weekday - 1];

        if (occupiedWeekdays.contains(day)) {
          confirmed.add(_dateOnly(date));
        }
      }

      if (!mounted) return;

      setState(() {
        unavailableDates = confirmed;
        tentativeDates = tentative.difference(confirmed);
      });
    } catch (error) {
      debugPrint('Failed to load room availability: $error');
    }
  }

  Future<void> loadSelectedDateAvailability() async {
    if (selectedRoom == null || selectedDate == null) return;

    setState(() {
      isLoadingDateAvailability = true;
      selectedDateBookings.clear();
      selectedDatePendingBookings.clear();
      availableTimeRanges.clear();
    });

    final firestore = FirebaseFirestore.instance;

    final dateStart = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
    );

    final nextDate = dateStart.add(const Duration(days: 1));

    final bookings = <Map<String, dynamic>>[];
    final pendingBookings = <Map<String, dynamic>>[];

    void addBooking(Map<String, dynamic> data, String title, String status) {
      final start = data['startTimeMinutes'];
      final end = data['endTimeMinutes'];

      if (start is! num || end is! num) return;

      final startMinutes = start.toInt();
      final endMinutes = end.toInt();

      if (endMinutes <= operatingStartMinutes ||
          startMinutes >= operatingEndMinutes ||
          endMinutes <= startMinutes) {
        return;
      }

      final booking = <String, dynamic>{
        'start': startMinutes.clamp(operatingStartMinutes, operatingEndMinutes),
        'end': endMinutes.clamp(operatingStartMinutes, operatingEndMinutes),
        'title': title,
        'status': status,
      };

      if (status == 'approved') {
        bookings.add(booking);
      } else if (status == 'pending') {
        pendingBookings.add(booking);
      }
    }

    try {
      // 1. Campus Events
      final eventsSnapshot = await firestore
          .collection('events')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(nextDate))
          .get();

      for (final doc in eventsSnapshot.docs) {
        final data = doc.data();

        if (data['location']?.toString() != selectedRoom) continue;

        final status = data['status']?.toString().toLowerCase();

        addBooking(
          data,
          data['title']?.toString() ?? 'Campus Event',
          status ?? '',
        );
      }

      // 2. Club Activities
      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('status', whereIn: ['approved', 'pending'])
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(nextDate))
          .get();

      for (final doc in activitiesSnapshot.docs) {
        final data = doc.data();

        if (data['roomName']?.toString() != selectedRoom) continue;

        addBooking(
          data,
          data['activityTitle']?.toString() ?? 'Club Activity',
          data['status']?.toString().toLowerCase() ?? '',
        );
      }

      // 3. Active class schedules
      final classesSnapshot = await firestore
          .collection('classes')
          .where('status', isEqualTo: 'active')
          .get();

      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      final selectedDay = weekdays[selectedDate!.weekday - 1];

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final schedules = classData['schedules'];

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;

          if (schedule['roomName']?.toString() != selectedRoom) continue;
          if (schedule['dayOfWeek']?.toString() != selectedDay) continue;

          final start = schedule['startTimeMinutes'];
          final end = schedule['endTimeMinutes'];

          if (start is! num || end is! num) continue;

          addBooking(
            {'startTimeMinutes': start, 'endTimeMinutes': end},
            classData['subjectName']?.toString() ?? 'Class Schedule',
            'approved',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        selectedDateBookings = bookings;
        selectedDatePendingBookings = pendingBookings;
        _calculateAvailableTimeRanges();
        isLoadingDateAvailability = false;
      });
    } catch (error) {
      debugPrint('Failed to load selected date availability: $error');

      if (!mounted) return;

      setState(() {
        isLoadingDateAvailability = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load availability: $error')),
      );
    }
  }

  Future<void> _pickDate() async {
    if (selectedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room first.')),
      );
      return;
    }

    DateTime dialogFocusedDay = focusedDay;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: const Text('Room Availability'),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Availability for $selectedRoom',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),

                    TableCalendar<String>(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: dialogFocusedDay,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Month',
                      },
                      selectedDayPredicate: (day) {
                        return selectedDate != null &&
                            isSameDay(selectedDate, day);
                      },
                      eventLoader: (day) {
                        final date = _dateOnly(day);

                        if (unavailableDates.contains(date)) {
                          return ['confirmed'];
                        }

                        if (tentativeDates.contains(date)) {
                          return ['pending'];
                        }

                        return [];
                      },
                      onDaySelected: (selectedDay, focusedDayValue) {
                        setState(() {
                          selectedDate = _dateOnly(selectedDay);
                          focusedDay = focusedDayValue;

                          startTime = null;
                          endTime = null;
                        });

                        Navigator.pop(dialogContext);

                        loadSelectedDateAvailability();
                      },
                      onPageChanged: (newFocusedDay) async {
                        dialogSetState(() {
                          dialogFocusedDay = newFocusedDay;
                        });

                        focusedDay = newFocusedDay;

                        await loadMonthlyAvailability(newFocusedDay);

                        dialogSetState(() {});
                      },
                      calendarBuilders: CalendarBuilders<String>(
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return null;

                          final isConfirmed = events.contains('confirmed');

                          return Positioned(
                            bottom: 5,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isConfirmed ? Colors.red : Colors.orange,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text('Booked'),
                        const SizedBox(width: 16),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text('Pending'),
                      ],
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Marked dates may still have available time slots. '
                      'Choose a date to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
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

    if (start < operatingStartMinutes ||
        end > operatingEndMinutes ||
        end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a valid time between 8:00 AM and 9:00 PM.',
          ),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Please log in first.');

      final firestore = FirebaseFirestore.instance;
      final dateStart = _dateOnly(selectedDate!);
      final dateEnd = dateStart.add(const Duration(days: 1));

      // Check active classroom schedules.
      final classesSnapshot = await firestore
          .collection('classes')
          .where('status', isEqualTo: 'active')
          .get();

      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      final selectedDay = weekdays[selectedDate!.weekday - 1];

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final schedules = classData['schedules'];

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;
          if (schedule['roomName']?.toString() != selectedRoom) continue;
          if (schedule['dayOfWeek']?.toString() != selectedDay) continue;

          final oldStart = schedule['startTimeMinutes'];
          final oldEnd = schedule['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          if (_hasTimeOverlap(oldStart.toInt(), oldEnd.toInt(), start, end)) {
            throw Exception(
              '$selectedRoom is already assigned to '
              '${classData['subjectName'] ?? 'a class'} on $selectedDay.',
            );
          }
        }
      }

      // Check approved Campus Events.
      final eventsSnapshot = await firestore
          .collection('events')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(dateEnd))
          .get();

      for (final event in eventsSnapshot.docs) {
        final data = event.data();

        if (data['location']?.toString() != selectedRoom) continue;
        if (data['status']?.toString().toLowerCase() != 'approved') {
          continue;
        }

        final oldStart = data['startTimeMinutes'];
        final oldEnd = data['endTimeMinutes'];

        if (oldStart is! num || oldEnd is! num) continue;

        if (_hasTimeOverlap(oldStart.toInt(), oldEnd.toInt(), start, end)) {
          throw Exception(
            '$selectedRoom is already booked by an approved Campus Event.',
          );
        }
      }

      // Check approved Club Activities.
      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('status', isEqualTo: 'approved')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(dateEnd))
          .get();

      for (final activity in activitiesSnapshot.docs) {
        final data = activity.data();

        if (data['roomName']?.toString() != selectedRoom) continue;
        if (data['status']?.toString().toLowerCase() != 'approved') {
          continue;
        }

        final oldStart = data['startTimeMinutes'];
        final oldEnd = data['endTimeMinutes'];

        if (oldStart is! num || oldEnd is! num) continue;

        if (_hasTimeOverlap(oldStart.toInt(), oldEnd.toInt(), start, end)) {
          throw Exception(
            '$selectedRoom is already booked by another Club Activity.',
          );
        }
      }

      // Save the new activity request as pending.
      final userDoc = await firestore.collection('users').doc(user.uid).get();

      final clubDoc = await firestore
          .collection('clubs')
          .doc(widget.clubId)
          .get();

      debugPrint('--- CLUB ACTIVITY PERMISSION CHECK ---');
      debugPrint('User role: ${userDoc.data()?['role']}');
      debugPrint('Club exists: ${clubDoc.exists}');
      debugPrint('Club status: ${clubDoc.data()?['status']}');
      debugPrint(
        'Club advisor matches user: ${clubDoc.data()?['advisorId'] == user.uid}',
      );
      debugPrint(
        'Widget advisor matches user: ${widget.advisorId == user.uid}',
      );
      debugPrint('--------------------------------------');
      final activityData = {
        'activityTitle': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'clubId': widget.clubId,
        'clubName': widget.clubName,
        'advisorId': widget.advisorId,
        'roomName': selectedRoom,
        'date': Timestamp.fromDate(dateStart),
        'startTimeMinutes': start,
        'endTimeMinutes': end,
        'status': 'pending',
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

      debugPrint('ACTIVITY DATA: $activityData');

      debugPrint(
        'FIRESTORE PROJECT: ${FirebaseFirestore.instance.app.options.projectId}',
      );
      debugPrint(
        'FIRESTORE DATABASE: ${FirebaseFirestore.instance.databaseId}',
      );
      debugPrint('AUTH UID: ${FirebaseAuth.instance.currentUser?.uid}');

      final clubCheck = await firestore
          .collection('clubs')
          .doc(widget.clubId)
          .get();

      debugPrint('CLUB DOCUMENT ID: ${clubCheck.id}');
      debugPrint('CLUB DOCUMENT DATA: ${clubCheck.data()}');

      await firestore.collection('club_activities').add(activityData);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Club activity request submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit activity: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (startTime ?? TimeOfDay.now())
          : (endTime ?? TimeOfDay.now()),
    );

    if (!mounted) return;

    if (picked != null) {
      final pickedMinutes = _toMinutes(picked);

      if (pickedMinutes < operatingStartMinutes ||
          pickedMinutes > operatingEndMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please choose a time between 8:00 AM and 9:00 PM.'),
          ),
        );
        return;
      }

      setState(() {
        if (isStart) {
          startTime = picked;
        } else {
          endTime = picked;
        }
      });
    }
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

      final firestore = FirebaseFirestore.instance;

      // Validate room availability before approving.
      if (status == 'approved') {
        final activityDoc = await firestore
            .collection('club_activities')
            .doc(activityId)
            .get();

        if (!activityDoc.exists) {
          throw Exception('Club activity not found.');
        }

        final data = activityDoc.data()!;
        final roomName = data['roomName']?.toString();
        final dateValue = data['date'];
        final start = data['startTimeMinutes'];
        final end = data['endTimeMinutes'];

        if (roomName == null ||
            dateValue is! Timestamp ||
            start is! num ||
            end is! num) {
          throw Exception('Activity has incomplete room or schedule details.');
        }

        final activityDate = dateValue.toDate();

        final activityDay = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ][activityDate.weekday - 1];

        // Check active classroom schedules.
        final classesSnapshot = await firestore
            .collection('classes')
            .where('status', isEqualTo: 'active')
            .get();

        for (final classDoc in classesSnapshot.docs) {
          final classData = classDoc.data();
          final schedules = classData['schedules'];

          if (schedules is! List) continue;

          for (final schedule in schedules) {
            if (schedule is! Map) continue;

            if (schedule['dayOfWeek']?.toString() != activityDay) continue;
            if (schedule['roomName']?.toString() != roomName) continue;

            final oldStart = schedule['startTimeMinutes'];
            final oldEnd = schedule['endTimeMinutes'];

            if (oldStart is! num || oldEnd is! num) continue;

            if (oldStart.toInt() < end.toInt() &&
                oldEnd.toInt() > start.toInt()) {
              throw Exception(
                '$roomName is already assigned to '
                '${classData['subjectName'] ?? 'a class'} on $activityDay.',
              );
            }
          }
        }

        // Get the selected activity's date range.
        final eventDateStart = DateTime(
          activityDate.year,
          activityDate.month,
          activityDate.day,
        );

        final eventDateEnd = eventDateStart.add(const Duration(days: 1));

        // Check approved Campus Events.
        final eventsSnapshot = await firestore
            .collection('events')
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(eventDateStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(eventDateEnd))
            .get();

        for (final event in eventsSnapshot.docs) {
          final eventData = event.data();

          if (eventData['location']?.toString() != roomName) continue;

          if (eventData['status']?.toString().toLowerCase() != 'approved') {
            continue;
          }

          final oldStart = eventData['startTimeMinutes'];
          final oldEnd = eventData['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          if (oldStart.toInt() < end.toInt() &&
              oldEnd.toInt() > start.toInt()) {
            throw Exception(
              '$roomName is already booked by an approved Campus Event.',
            );
          }
        }

        // Check other Club Activities on the same date.
        final activitiesSnapshot = await firestore
            .collection('club_activities')
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(eventDateStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(eventDateEnd))
            .get();

        for (final otherActivity in activitiesSnapshot.docs) {
          if (otherActivity.id == activityId) continue;

          final otherData = otherActivity.data();

          if (otherData['status']?.toString().toLowerCase() != 'approved') {
            continue;
          }

          if (otherData['roomName']?.toString() != roomName) continue;

          final oldStart = otherData['startTimeMinutes'];
          final oldEnd = otherData['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          if (oldStart.toInt() < end.toInt() &&
              oldEnd.toInt() > start.toInt()) {
            throw Exception(
              '$roomName is already booked by another Club Activity.',
            );
          }
        }
      }

      // Update the activity status.
      await firestore.collection('club_activities').doc(activityId).update({
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
              onChanged: (value) async {
                setState(() {
                  selectedRoom = value;

                  // Reset the previously selected date and times.
                  selectedDate = null;
                  startTime = null;
                  endTime = null;

                  // Clear the previous room's availability.
                  unavailableDates.clear();
                  tentativeDates.clear();
                  selectedDateBookings.clear();
                  selectedDatePendingBookings.clear();
                  availableTimeRanges.clear();
                });

                if (value != null) {
                  await loadMonthlyAvailability(focusedDay);
                }
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

            if (selectedDate != null) ...[
              const SizedBox(height: 8),

              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Room Availability',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Text(
                        'Operating hours: 8:00 AM – 9:00 PM',
                        style: TextStyle(fontSize: 12),
                      ),

                      const SizedBox(height: 10),

                      if (isLoadingDateAvailability)
                        const Center(child: CircularProgressIndicator())
                      else if (availableTimeRanges.isEmpty)
                        const Text(
                          'No available time ranges found.',
                          style: TextStyle(color: Colors.red),
                        )
                      else ...[
                        const Text(
                          'Available Times',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),

                        ...availableTimeRanges.map((range) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatMinutes(range['start']!)} – '
                                  '${_formatMinutes(range['end']!)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      if (selectedDatePendingBookings.isNotEmpty) ...[
                        const Divider(height: 20),
                        const Text(
                          'Pending Requests (Not Yet Confirmed)',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),

                        ...selectedDatePendingBookings.map((booking) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${booking['title']}: '
                              '${_formatMinutes(booking['start'] as int)} – '
                              '${_formatMinutes(booking['end'] as int)}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ],

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

  final TextEditingController rejectionReasonController =
      TextEditingController();

  @override
  void dispose() {
    rejectionReasonController.dispose();
    super.dispose();
  }

  String formatTime(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

    return time.format(context);
  }

  Future<void> updateActivityStatus(String activityId, String status) async {
    final rejectionFormKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          status == 'approved' ? 'Approve Activity?' : 'Reject Activity?',
        ),
        content: status == 'approved'
            ? const Text('Are you sure you want to approve this club activity?')
            : Form(
                key: rejectionFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please provide a justification for rejecting this '
                      'club activity request.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: rejectionReasonController,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Justification Reason',
                        hintText: 'Explain why this request is rejected...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Justification reason is required.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (status == 'rejected' &&
                  !(rejectionFormKey.currentState?.validate() ?? false)) {
                return;
              }

              Navigator.pop(
                dialogContext,
                status == 'approved'
                    ? 'approved'
                    : rejectionReasonController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'approved' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(status == 'approved' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    final rejectionReason = status == 'rejected' ? result : null;

    if (result == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Please log in first.');
      }

      final firestore = FirebaseFirestore.instance;

      // Validate room availability before approving.
      if (status == 'approved') {
        final activityDoc = await firestore
            .collection('club_activities')
            .doc(activityId)
            .get();

        if (!activityDoc.exists) {
          throw Exception('Club activity not found.');
        }

        final data = activityDoc.data()!;
        final roomName = data['roomName']?.toString();
        final dateValue = data['date'];
        final start = data['startTimeMinutes'];
        final end = data['endTimeMinutes'];

        if (roomName == null ||
            dateValue is! Timestamp ||
            start is! num ||
            end is! num) {
          throw Exception('Activity has incomplete room or schedule details.');
        }

        final activityDate = dateValue.toDate();
        final activityDay = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ][activityDate.weekday - 1];

        // Check active classroom schedules.
        final classesSnapshot = await firestore
            .collection('classes')
            .where('status', isEqualTo: 'active')
            .get();

        for (final classDoc in classesSnapshot.docs) {
          final classData = classDoc.data();
          final schedules = classData['schedules'];

          if (schedules is! List) continue;

          for (final schedule in schedules) {
            if (schedule is! Map) continue;

            if (schedule['dayOfWeek']?.toString() != activityDay) continue;
            if (schedule['roomName']?.toString() != roomName) continue;

            final oldStart = schedule['startTimeMinutes'];
            final oldEnd = schedule['endTimeMinutes'];

            if (oldStart is! num || oldEnd is! num) continue;

            if (oldStart.toInt() < end.toInt() &&
                oldEnd.toInt() > start.toInt()) {
              throw Exception(
                '$roomName is already assigned to '
                '${classData['subjectName'] ?? 'a class'} on $activityDay.',
              );
            }
          }
        }

        // Get the activity's date range.
        final eventDateStart = DateTime(
          activityDate.year,
          activityDate.month,
          activityDate.day,
        );

        final eventDateEnd = eventDateStart.add(const Duration(days: 1));

        // Check approved Campus Events.
        final eventsSnapshot = await firestore
            .collection('events')
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(eventDateStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(eventDateEnd))
            .get();

        for (final event in eventsSnapshot.docs) {
          final eventData = event.data();

          if (eventData['location']?.toString() != roomName) continue;

          final status = eventData['status']?.toString().toLowerCase();

          // Only approved events block the room.
          if (status != 'approved') continue;

          final oldStart = eventData['startTimeMinutes'];
          final oldEnd = eventData['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          if (oldStart.toInt() < end.toInt() &&
              oldEnd.toInt() > start.toInt()) {
            throw Exception(
              '$roomName is already booked by an approved Campus Event.',
            );
          }
        }

        // Check other approved Club Activities on the same date.
        final activitiesSnapshot = await firestore
            .collection('club_activities')
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(eventDateStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(eventDateEnd))
            .get();

        for (final otherActivity in activitiesSnapshot.docs) {
          if (otherActivity.id == activityId) continue;

          final otherData = otherActivity.data();

          if (otherData['status'] != 'approved') continue;
          if (otherData['roomName']?.toString() != roomName) continue;

          final oldStart = otherData['startTimeMinutes'];
          final oldEnd = otherData['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          if (oldStart.toInt() < end.toInt() &&
              oldEnd.toInt() > start.toInt()) {
            throw Exception(
              '$roomName is already booked by another Club Activity.',
            );
          }
        }
      }

      await firestore.collection('club_activities').doc(activityId).update({
        'status': status,
        'reviewedBy': user.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
        if (status == 'rejected') 'rejectionReason': rejectionReason!,
        if (status == 'approved') 'rejectionReason': FieldValue.delete(),
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

class AdvisorClubActivityRequestsPage extends StatefulWidget {
  final String advisorId;
  final String clubId;
  final String clubName;

  const AdvisorClubActivityRequestsPage({
    super.key,
    required this.advisorId,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<AdvisorClubActivityRequestsPage> createState() =>
      _AdvisorClubActivityRequestsPageState();
}

class _AdvisorClubActivityRequestsPageState
    extends State<AdvisorClubActivityRequestsPage> {
  String selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Club Activity Requests'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('club_activities')
            .where('advisorId', isEqualTo: widget.advisorId)
            .where('clubId', isEqualTo: widget.clubId)
            .where('status', whereIn: ['pending', 'approved', 'rejected'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to load your activity requests.'),
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

            final aTime = aDate is Timestamp ? aDate.millisecondsSinceEpoch : 0;
            final bTime = bDate is Timestamp ? bDate.millisecondsSinceEpoch : 0;

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
                    ? const Center(child: Text('No activity requests found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredActivities.length,
                        itemBuilder: (context, index) {
                          final data = filteredActivities[index].data();
                          final status = data['status'] ?? 'pending';
                          final rejectionReason =
                              data['rejectionReason']?.toString().trim() ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['activityTitle'] ??
                                        'Untitled Activity',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Club: ${data['clubName'] ?? widget.clubName}',
                                  ),
                                  Text(
                                    'Room: ${data['roomName'] ?? 'Not specified'}',
                                  ),
                                  Text(
                                    'Description: ${data['description'] ?? 'No description'}',
                                  ),
                                  const SizedBox(height: 8),
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
                                  if (status == 'rejected') ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Admin Justification',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            rejectionReason.isEmpty
                                                ? 'No rejection reason provided.'
                                                : rejectionReason,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
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
