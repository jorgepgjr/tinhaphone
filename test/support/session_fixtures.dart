import 'package:tinhaphone/auth/mobile_session.dart';

const teacherSession = MobileSession(
  token: 'teacher-token',
  baseUrl: 'http://localhost:8000',
  account: MobileAccount(
    id: '1',
    name: 'Professora',
    email: 'teacher@test.com',
    profile: 'PROFESSOR',
    schoolId: 1,
    schoolName: 'Escola Um',
  ),
);
const otherTeacherSession = MobileSession(
  token: 'other-token',
  baseUrl: 'http://localhost:8000',
  account: MobileAccount(
    id: '2',
    name: 'Professor',
    email: 'other@test.com',
    profile: 'PROFESSOR',
    schoolId: 2,
    schoolName: 'Escola Dois',
  ),
);
const familySession = MobileSession(
  token: 'family-token',
  baseUrl: 'http://localhost:8000',
  account: MobileAccount(
    id: 'parent',
    name: 'Familiar',
    email: 'family@test.com',
    profile: 'FAMILIAR',
    schoolId: 1,
    schoolName: 'Escola Um',
  ),
);

class MemoryTokenStore implements TokenStore {
  String? value;
  MemoryTokenStore([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
