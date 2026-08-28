import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/smart_move_widgets.dart';
import 'auth_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> _editProfile() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EditProfilePage()));
    if (updated == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile name updated.')));
    }
  }

  Future<void> _resetPassword() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ResetPasswordPage()));
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
    }
  }

  Future<void> _choosePreferredTransport() async {
    final state = context.read<AppState>();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBackground,
      builder: (sheetContext) => SafeArea(
        child: _PreferenceOptions<String>(
          title: 'Preferred transport',
          selected: state.preferredTransport,
          options: const [
            'Bus, rail & walking',
            'Rail + walking',
            'Bus + walking',
          ],
          label: (value) => value,
          onSelected: (value) => Navigator.of(sheetContext).pop(value),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await state.updatePreferredTransport(selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: 'Profile',
            avatarLabel: avatarInitials(state.profileName),
          ),
          const SizedBox(height: 22),
          PageTitle(
            kicker: 'PERSONALISE YOUR TRIP',
            title: 'Profile & settings',
            trailing: AvatarChip(
              size: 29,
              label: avatarInitials(state.profileName),
            ),
          ),
          const SizedBox(height: 17),
          if (state.isGuest)
            SoftCard(
              color: kPurpleSoft,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_person_outlined,
                    size: 24,
                    color: kPurple,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest mode',
                          style: TextStyle(
                            fontSize: 10,
                            color: kInk,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Sign in to save favourite routes and sync preferences',
                          style: TextStyle(fontSize: 8.5, color: kMutedDark),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    ),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            )
          else
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AvatarChip(
                        size: 38,
                        label: avatarInitials(state.profileName),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.profileName,
                              style: const TextStyle(
                                fontSize: 11,
                                color: kInk,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state.profileEmail,
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ProfileActionButton(
                    icon: Icons.edit_outlined,
                    title: 'Edit profile',
                    subtitle: 'Change your display name',
                    backgroundColor: kTealSoft,
                    iconColor: kTeal,
                    onPressed: _editProfile,
                  ),
                  const SizedBox(height: 8),
                  ProfileActionButton(
                    icon: Icons.lock_reset_rounded,
                    title: 'Reset password',
                    subtitle: 'Choose a new account password',
                    backgroundColor: kPurpleSoft,
                    iconColor: kPurple,
                    onPressed: _resetPassword,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          ProfileSetting(
            icon: Icons.directions_transit_rounded,
            label: 'PREFERRED TRANSPORT',
            value: state.preferredTransport,
            onTap: _choosePreferredTransport,
          ),
          const SizedBox(height: 12),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Journey notifications',
                        style: TextStyle(
                          fontSize: 9,
                          color: kInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Departure, delays and approaching stops',
                        style: TextStyle(fontSize: 8.5, color: kMuted),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: state.notificationsEnabled,
                  onChanged: context.read<AppState>().setNotifications,
                  activeThumbColor: Colors.white,
                  activeTrackColor: kTeal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          if (!state.isGuest) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);
                  await appState.signOut();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Signed out.')),
                  );
                },
                icon: const Icon(Icons.logout_rounded, size: 15),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _displayNameValidator(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter your name';
  if (!RegExp(r"^[a-zA-ZÀ-ÿ' -]+$").hasMatch(name)) {
    return 'Use letters, spaces, hyphens, or apostrophes';
  }
  return null;
}

String? _passwordValidator(String? value) {
  if (value == null || value.length < 6) return 'Use at least 6 characters';
  return null;
}

class ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;

  const ProfileActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: iconColor.withAlpha(30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 11,
                          color: kInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: kMutedDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 21, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<AppState>().profileName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final state = context.read<AppState>();
      await state.saveProfile(
        name: _nameController.text.trim(),
        email: state.profileEmail,
      );
      if (state.supabaseConfigured) await state.syncProfile();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Form(
            key: _formKey,
            child: SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update your profile name',
                    style: TextStyle(
                      fontSize: 18,
                      color: kInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'This name is shown on your MyTransitAssist profile.',
                    style: TextStyle(fontSize: 13, color: kMutedDark),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    validator: _displayNameValidator,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      hintText: 'Enter your name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().updatePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update password: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Form(
            key: _formKey,
            child: SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update your password',
                    style: TextStyle(
                      fontSize: 18,
                      color: kInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Enter your current password, then choose a new one.',
                    style: TextStyle(fontSize: 13, color: kMutedDark),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _currentPasswordController,
                    autofocus: true,
                    obscureText: true,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your current password'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: _passwordValidator,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: true,
                    validator: (value) {
                      final passwordError = _passwordValidator(value);
                      if (passwordError != null) return passwordError;
                      return value == _passwordController.text
                          ? null
                          : 'Passwords do not match';
                    },
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _update,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Updating…' : 'Update password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSetting extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const ProfileSetting({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final card = SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kPurpleSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: kPurple),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: KickerStyle.small),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 9,
                    color: kInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 16, color: kMuted),
        ],
      ),
    );
    return onTap == null ? card : GestureDetector(onTap: onTap, child: card);
  }
}

class _PreferenceOptions<T> extends StatelessWidget {
  final String title;
  final T selected;
  final List<T> options;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  const _PreferenceOptions({
    required this.title,
    required this.selected,
    required this.options,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: kInk,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...options.map(
            (value) => ListTile(
              onTap: () => onSelected(value),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                value == selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: value == selected ? kTeal : kMuted,
              ),
              title: Text(label(value)),
            ),
          ),
        ],
      ),
    );
  }
}
