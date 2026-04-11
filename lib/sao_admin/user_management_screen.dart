// lib/sao_admin/user_management_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // --- STATE VARIABLES ---
  String _searchQuery = '';
  String _selectedRoleFilter = 'All';
  String _sortBy = 'Newest';

  // Dummy data (Data Gatherer removed, only Academic Personnel remain)
  final List<Map<String, dynamic>> _allUsers = [
    {'name': 'Kirito (Kazuto Kirigaya)', 'id': 'CTU-2026-001', 'role': 'Instructor', 'dept': 'Computer Studies', 'status': 'Active', 'dateAdded': DateTime(2026, 4, 10)},
    {'name': 'Asuna Yuuki', 'id': 'CTU-2026-002', 'role': 'Instructor', 'dept': 'Arts and Sciences', 'status': 'Active', 'dateAdded': DateTime(2026, 4, 11)},
    {'name': 'Klein (Ryotaro Tsuboi)', 'id': 'CTU-2026-003', 'role': 'Department Head', 'dept': 'Engineering', 'status': 'Active', 'dateAdded': DateTime(2026, 4, 8)},
  ];

  final List<String> _departments = ['Computer Studies', 'Engineering', 'Education', 'Arts and Sciences', 'Business and Management', 'Technology', 'Nursing', 'Agriculture', 'N/A'];

  // 👈 Data Gatherer completely removed from available roles!
  final List<String> _roles = ['Instructor', 'Department Head'];

  // --- LOGIC: GET FILTERED AND SORTED USERS ---
  List<Map<String, dynamic>> get _filteredUsers {
    List<Map<String, dynamic>> filtered = _allUsers.where((user) {
      if (_selectedRoleFilter != 'All' && user['role'] != _selectedRoleFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final name = user['name'].toString().toLowerCase();
        final id = user['id'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!name.contains(query) && !id.contains(query)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      DateTime dateA = a['dateAdded'];
      DateTime dateB = b['dateAdded'];
      return _sortBy == 'Newest' ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    return filtered;
  }

  // ==========================================
  // "HOVER-LIKE" POP-UPS (DIALOGS)
  // ==========================================

  // 1. Edit User Pop-up
  void _showEditUserDialog(Map<String, dynamic> user) {
    TextEditingController nameController = TextEditingController(text: user['name']);
    TextEditingController idController = TextEditingController(text: user['id']);
    String selectedRole = user['role'];
    String selectedDept = user['dept'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Edit Profile & Role', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: idController,
                        decoration: const InputDecoration(labelText: 'ID Number', prefixIcon: Icon(Icons.badge, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.manage_accounts, color: AppColors.royalBlue)),
                        items: _roles.map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (val) => setDialogState(() => selectedRole = val!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedDept,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Department', prefixIcon: Icon(Icons.domain, color: AppColors.royalBlue)),
                        items: _departments.map((dept) => DropdownMenuItem(
                          value: dept,
                          child: Text(dept, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (val) => setDialogState(() => selectedDept = val!),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepBlue, foregroundColor: AppColors.white),
                    onPressed: () {
                      setState(() {
                        user['name'] = nameController.text;
                        user['id'] = idController.text;
                        user['role'] = selectedRole;
                        user['dept'] = selectedDept;
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile Updated Successfully'), backgroundColor: Colors.green));
                    },
                    child: const Text('Save Changes'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // 2. Reset Password Pop-up
  void _showResetPasswordDialog(Map<String, dynamic> user) {
    TextEditingController newPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Reset Password for ${user['name']}', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a new temporary password for this user.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: Icon(Icons.lock_reset, color: AppColors.gold),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.deepBlue),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password for ${user['name']} has been reset!'), backgroundColor: AppColors.royalBlue));
              },
              child: const Text('Confirm Reset', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // 3. Add New User Pop-up (The '+' Button)
  void _showAddUserDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController passwordController = TextEditingController();
    String selectedRole = 'Instructor'; // Default value
    String selectedDept = 'Computer Studies'; // Default value

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.person_add, color: AppColors.gold),
                    SizedBox(width: 12),
                    Text('Create New User', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Manually register a user and grant instant active access.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: idController,
                        decoration: const InputDecoration(labelText: 'ID Number', prefixIcon: Icon(Icons.badge, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Temporary Password', prefixIcon: Icon(Icons.lock, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.manage_accounts, color: AppColors.royalBlue)),
                        items: _roles.map((role) => DropdownMenuItem(value: role, child: Text(role, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setDialogState(() => selectedRole = val!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedDept,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Department', prefixIcon: Icon(Icons.domain, color: AppColors.royalBlue)),
                        items: _departments.map((dept) => DropdownMenuItem(value: dept, child: Text(dept, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setDialogState(() => selectedDept = val!),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.deepBlue),
                    onPressed: () {
                      setState(() {
                        _allUsers.insert(0, {
                          'name': nameController.text.isNotEmpty ? nameController.text : 'New User',
                          'id': idController.text.isNotEmpty ? idController.text : 'CTU-NEW',
                          'role': selectedRole,
                          'dept': selectedDept,
                          'status': 'Active',
                          'dateAdded': DateTime.now(),
                        });
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${nameController.text.isNotEmpty ? nameController.text : 'New User'} added successfully!'),
                          backgroundColor: Colors.green
                      ));
                    },
                    child: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // --- UI: BOTTOM SHEET FOR FILTERS ---
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter & Sort', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                  const SizedBox(height: 24),

                  const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                  Wrap(
                    spacing: 12,
                    children: ['Newest', 'Oldest'].map((sortType) {
                      return ChoiceChip(
                        label: Text(sortType),
                        selected: _sortBy == sortType,
                        selectedColor: AppColors.royalBlue.withOpacity(0.2),
                        labelStyle: TextStyle(color: _sortBy == sortType ? AppColors.deepBlue : Colors.grey),
                        onSelected: (bool selected) {
                          if (selected) {
                            setModalState(() => _sortBy = sortType);
                            setState(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  const Text('Filter By Role', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                  Wrap(
                    spacing: 12,
                    children: ['All', 'Instructor', 'Department Head'].map((role) {
                      return ChoiceChip(
                        label: Text(role),
                        selected: _selectedRoleFilter == role,
                        selectedColor: AppColors.royalBlue.withOpacity(0.2),
                        labelStyle: TextStyle(color: _selectedRoleFilter == role ? AppColors.deepBlue : Colors.grey),
                        onSelected: (bool selected) {
                          if (selected) {
                            setModalState(() => _selectedRoleFilter = role);
                            setState(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepBlue,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUsers = _filteredUsers;

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('User Management', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.gold),
            tooltip: 'Add New User Manually',
            onPressed: _showAddUserDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // SEARCH & FILTER BAR
            // ==========================================
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(12)),
                      child: TextField(
                        onChanged: (value) => setState(() => _searchQuery = value),
                        decoration: const InputDecoration(
                          hintText: 'Search by Name or ID...',
                          hintStyle: TextStyle(color: Colors.grey),
                          prefixIcon: Icon(Icons.search, color: AppColors.royalBlue),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: _selectedRoleFilter != 'All' ? AppColors.royalBlue : AppColors.royalBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.filter_list, color: _selectedRoleFilter != 'All' ? AppColors.white : AppColors.royalBlue),
                      onPressed: _showFilterBottomSheet,
                    ),
                  ),
                ],
              ),
            ),

            // ==========================================
            // USER LIST
            // ==========================================
            Expanded(
              child: currentUsers.isEmpty
                  ? const Center(child: Text("No users found matching your filters.", style: TextStyle(color: Colors.grey, fontSize: 16)))
                  : ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: currentUsers.length,
                itemBuilder: (context, index) {
                  final user = currentUsers[index];
                  final isActive = user['status'] == 'Active';

                  return Card(
                    color: AppColors.white,
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // User Avatar
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isActive ? AppColors.royalBlue.withOpacity(0.1) : Colors.grey.shade200,
                            child: Text(
                              user['name'][0],
                              style: TextStyle(color: isActive ? AppColors.deepBlue : Colors.grey, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // User Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isActive ? AppColors.darkGray : Colors.grey,
                                    decoration: isActive ? TextDecoration.none : TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('${user['id']} • ${user['role']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    user['status'],
                                    style: TextStyle(color: isActive ? Colors.green.shade700 : Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Admin Actions Dropdown (The 3 dots)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: AppColors.darkGray),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (value) {
                              if (value == 'Edit Profile & Role') {
                                _showEditUserDialog(user);
                              } else if (value == 'Reset Password') {
                                _showResetPasswordDialog(user);
                              } else if (value == 'Toggle Status') {
                                setState(() {
                                  user['status'] = isActive ? 'Disabled' : 'Active';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${user['name']} is now ${user['status']}'), backgroundColor: user['status'] == 'Active' ? Colors.green : Colors.red),
                                );
                              }
                            },
                            itemBuilder: (BuildContext context) => [
                              const PopupMenuItem(
                                value: 'Edit Profile & Role',
                                child: Row(children: [
                                  Icon(Icons.edit, color: AppColors.royalBlue, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(child: Text('Edit Profile & Role'))
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'Reset Password',
                                child: Row(children: [
                                  Icon(Icons.lock_reset, color: AppColors.gold, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(child: Text('Reset Password'))
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'Toggle Status',
                                child: Row(
                                  children: [
                                    Icon(isActive ? Icons.block : Icons.check_circle, color: isActive ? Colors.red : Colors.green, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(isActive ? 'Disable Account' : 'Enable Account', style: TextStyle(color: isActive ? Colors.red : Colors.green))
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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