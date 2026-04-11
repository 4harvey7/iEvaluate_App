// lib/sao_admin/personnel_management_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class PersonnelManagementScreen extends StatefulWidget {
  const PersonnelManagementScreen({super.key});

  @override
  State<PersonnelManagementScreen> createState() => _PersonnelManagementScreenState();
}

class _PersonnelManagementScreenState extends State<PersonnelManagementScreen> {
  // --- STATE VARIABLES ---
  String _searchQuery = '';
  String _selectedRoleFilter = 'All';
  String _sortBy = 'Newest';

  // Dummy data strictly for Administrative/Operational Personnel (Office removed)
  final List<Map<String, dynamic>> _allPersonnel = [
    {'name': 'Agil (Andrew Gilbert)', 'id': 'CTU-STAFF-001', 'role': 'Data Gatherer', 'status': 'Active', 'dateAdded': DateTime(2026, 4, 10)},
    {'name': 'Lisbeth (Rika Shinozaki)', 'id': 'CTU-STAFF-002', 'role': 'Data Gatherer', 'status': 'Active', 'dateAdded': DateTime(2026, 4, 11)},
    {'name': 'Yui', 'id': 'CTU-ADMIN-001', 'role': 'System Admin', 'status': 'Disabled', 'dateAdded': DateTime(2026, 4, 8)},
  ];

  // Specific list for Operational Staff
  final List<String> _roles = ['Data Gatherer', 'System Admin'];

  // --- LOGIC: GET FILTERED AND SORTED PERSONNEL ---
  List<Map<String, dynamic>> get _filteredPersonnel {
    List<Map<String, dynamic>> filtered = _allPersonnel.where((person) {
      if (_selectedRoleFilter != 'All' && person['role'] != _selectedRoleFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final name = person['name'].toString().toLowerCase();
        final id = person['id'].toString().toLowerCase();
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
  // POP-UPS (DIALOGS) FOR PERSONNEL
  // ==========================================

  // 1. Edit Personnel Pop-up
  void _showEditPersonnelDialog(Map<String, dynamic> person) {
    TextEditingController nameController = TextEditingController(text: person['name']);
    TextEditingController idController = TextEditingController(text: person['id']);
    String selectedRole = person['role'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Edit Personnel', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
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
                        decoration: const InputDecoration(labelText: 'Staff ID', prefixIcon: Icon(Icons.badge, color: AppColors.royalBlue)),
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
                        person['name'] = nameController.text;
                        person['id'] = idController.text;
                        person['role'] = selectedRole;
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personnel Updated Successfully'), backgroundColor: Colors.green));
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

  // 2. Add New Personnel Pop-up
  void _showAddPersonnelDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController passwordController = TextEditingController();
    String selectedRole = 'Data Gatherer';

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
                    Icon(Icons.person_add_alt_1, color: AppColors.gold),
                    SizedBox(width: 12),
                    Expanded(child: Text('Add Personnel', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold))),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Register new operational staff (e.g. Data Gatherers).', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person, color: AppColors.royalBlue)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: idController,
                        decoration: const InputDecoration(labelText: 'Staff ID', prefixIcon: Icon(Icons.badge, color: AppColors.royalBlue)),
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
                        _allPersonnel.insert(0, {
                          'name': nameController.text.isNotEmpty ? nameController.text : 'New Staff',
                          'id': idController.text.isNotEmpty ? idController.text : 'CTU-STAFF-NEW',
                          'role': selectedRole,
                          'status': 'Active',
                          'dateAdded': DateTime.now(),
                        });
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${nameController.text.isNotEmpty ? nameController.text : 'New Staff'} added successfully!'),
                          backgroundColor: Colors.green
                      ));
                    },
                    child: const Text('Create Staff', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // 3. Bottom Sheet Filter
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
                  const Text('Filter Staff', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
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
                    children: ['All', 'Data Gatherer', 'System Admin'].map((role) {
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
    final currentPersonnel = _filteredPersonnel;

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Personnel Management', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppColors.gold),
            tooltip: 'Add New Staff',
            onPressed: _showAddPersonnelDialog,
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
                          hintText: 'Search Staff Name or ID...',
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
            // PERSONNEL LIST
            // ==========================================
            Expanded(
              child: currentPersonnel.isEmpty
                  ? const Center(child: Text("No personnel found matching your filters.", style: TextStyle(color: Colors.grey, fontSize: 16)))
                  : ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: currentPersonnel.length,
                itemBuilder: (context, index) {
                  final person = currentPersonnel[index];
                  final isActive = person['status'] == 'Active';

                  return Card(
                    color: AppColors.white,
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isActive ? AppColors.royalBlue.withOpacity(0.1) : Colors.grey.shade200,
                            child: Text(
                              person['name'][0],
                              style: TextStyle(color: isActive ? AppColors.deepBlue : Colors.grey, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isActive ? AppColors.darkGray : Colors.grey,
                                    decoration: isActive ? TextDecoration.none : TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Subtitle updated: no office
                                Text('${person['id']} • ${person['role']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    person['status'],
                                    style: TextStyle(color: isActive ? Colors.green.shade700 : Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Action Menu
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: AppColors.darkGray),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (value) {
                              if (value == 'Edit') {
                                _showEditPersonnelDialog(person);
                              } else if (value == 'Reset') {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset link sent for ${person['name']}'), backgroundColor: AppColors.royalBlue));
                              } else if (value == 'Toggle') {
                                setState(() {
                                  person['status'] = isActive ? 'Disabled' : 'Active';
                                });
                              }
                            },
                            itemBuilder: (BuildContext context) => [
                              const PopupMenuItem(
                                value: 'Edit',
                                child: Row(children: [
                                  Icon(Icons.edit, color: AppColors.royalBlue, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(child: Text('Edit Personnel'))
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'Reset',
                                child: Row(children: [
                                  Icon(Icons.lock_reset, color: AppColors.gold, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(child: Text('Reset Password'))
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'Toggle',
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