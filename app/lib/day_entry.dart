// Справочники для записи дня и удобная обёртка над записью.

class Opt {
  final String id;
  final String emoji;
  final String label;
  const Opt(this.id, this.emoji, this.label);
}

const symptomOptions = <Opt>[
  Opt('cramps', '😖', 'Спазмы в животе'),
  Opt('back', '💢', 'Боль в спине'),
  Opt('headache', '🤕', 'Головная боль'),
  Opt('migraine', '💥', 'Мигрень'),
  Opt('bloating', '🎈', 'Вздутие'),
  Opt('breast', '🌸', 'Чувствительность груди'),
  Opt('acne', '🔴', 'Высыпания'),
  Opt('fatigue', '😩', 'Усталость'),
  Opt('insomnia', '🌙', 'Бессонница'),
  Opt('nausea', '🤢', 'Тошнота'),
  Opt('dizzy', '💫', 'Головокружение'),
  Opt('spotting', '🩸', 'Мажущие выделения'),
  Opt('discharge', '💧', 'Выделения'),
  Opt('cravings', '🍫', 'Тяга к сладкому'),
  Opt('hunger', '🍝', 'Голод'),
  Opt('hot', '🔥', 'Приливы жара'),
  Opt('chills', '❄️', 'Озноб'),
  Opt('muscle', '💪', 'Мышечная боль'),
  Opt('swelling', '💦', 'Отёки'),
  Opt('diarrhea', '🧻', 'Диарея'),
  Opt('constipation', '😣', 'Запор'),
  Opt('pms', '🌩️', 'ПМС'),
  Opt('tension', '⚡', 'Напряжение'),
  Opt('itch', '🌵', 'Зуд'),
  Opt('fever', '🌡️', 'Температура'),
  Opt('focus', '🧩', 'Трудно сосредоточиться'),
];

const moodOptions = <Opt>[
  Opt('happy', '😊', 'Счастливая'),
  Opt('calm', '😌', 'Спокойная'),
  Opt('energetic', '🤩', 'Энергичная'),
  Opt('love', '😍', 'Влюблённая'),
  Opt('playful', '😜', 'Игривая'),
  Opt('confident', '😎', 'Уверенная'),
  Opt('normal', '😐', 'Нормальная'),
  Opt('sleepy', '😴', 'Сонная'),
  Opt('sad', '😢', 'Печальная'),
  Opt('anxious', '😟', 'Встревоженная'),
  Opt('irritable', '😠', 'Раздражённая'),
  Opt('angry', '😡', 'Сердитая'),
  Opt('moody', '🎭', 'Переменчивая'),
  Opt('stressed', '😫', 'В стрессе'),
  Opt('down', '😞', 'Подавленная'),
  Opt('emotional', '🥺', 'Эмоциональная'),
  Opt('lonely', '😔', 'Одинокая'),
  Opt('sick', '😷', 'Больная'),
  Opt('excited', '😆', 'Взволнованная'),
  Opt('sensual', '😏', 'Чувственная'),
];

const intimacyOptions = <Opt>[
  Opt('unprotected', '❤️', 'Незащищённый секс'),
  Opt('protected', '🛡️', 'Защищённый секс'),
  Opt('masturbation', '💜', 'Мастурбация'),
  Opt('kisses', '💋', 'Поцелуи'),
];

const contraceptionMethods = <Opt>[
  Opt('pill', '💊', 'Противозачаточные таблетки'),
  Opt('patch', '🩹', 'Пластырь'),
  Opt('iud', '📍', 'ВМС'),
  Opt('ring', '⭕', 'Гормональное кольцо'),
  Opt('injection', '💉', 'Инъекция'),
  Opt('implant', '🔹', 'Имплантат'),
];

const flowLabels = ['Скудные', 'Умеренные', 'Обильные', 'Очень обильные'];

/// Разделы экрана записи дня (их можно скрывать и переставлять).
class Section {
  final String id;
  final String title;
  const Section(this.id, this.title);
}

const allSections = <Section>[
  Section('flow', 'Обильность месячных'),
  Section('intimacy', 'Сексуальная активность'),
  Section('symptoms', 'Симптомы'),
  Section('moods', 'Настроение'),
  Section('pill', 'Контрацепция'),
  Section('notes', 'Заметки'),
  Section('meds', 'Медицинские препараты'),
  Section('temp', 'Температура'),
  Section('weight', 'Вес'),
];

/// Свои пункты хранятся с префиксом «c:», эмодзи для них — точка.
Opt optById(List<Opt> base, String id) {
  for (final o in base) {
    if (o.id == id) return o;
  }
  if (id.startsWith('c:')) return Opt(id, '✳️', id.substring(2));
  return Opt(id, '•', id);
}

/// Обёртка над записью дня: значения хранятся компактно в Map.
/// p — месячные, f — обильность 1..4, s — симптомы, m — настроение,
/// x — интим, pl — таблетка принята, md — лекарства, t — температура,
/// w — вес, n — заметка.
class DayData {
  final Map<String, dynamic> raw;
  const DayData(this.raw);

  static const empty = DayData({});

  bool get period => raw['p'] == true;
  int get flow => (raw['f'] as num?)?.toInt() ?? 0;
  List<String> _list(String k) =>
      (raw[k] is List) ? (raw[k] as List).map((e) => '$e').toList() : const [];
  List<String> get symptoms => _list('s');
  List<String> get moods => _list('m');
  List<String> get intimacy => _list('x');
  List<String> get meds => _list('md');
  bool get pill => raw['pl'] == true;
  double? get temp => (raw['t'] as num?)?.toDouble();
  double? get weight => (raw['w'] as num?)?.toDouble();
  String get note => (raw['n'] as String?) ?? '';

  /// Есть ли в записи что-то кроме отметки месячных.
  bool get hasLog =>
      flow > 0 ||
      symptoms.isNotEmpty ||
      moods.isNotEmpty ||
      intimacy.isNotEmpty ||
      meds.isNotEmpty ||
      pill ||
      temp != null ||
      weight != null ||
      note.trim().isNotEmpty;

  bool get isEmpty => !period && !hasLog;

  /// Нормализует изменения: пустые значения удаляются.
  static Map<String, dynamic> merge(
      Map<String, dynamic> base, Map<String, dynamic> changes) {
    final r = Map<String, dynamic>.from(base);
    changes.forEach((k, v) {
      final emptyVal = v == null ||
          v == false ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty) ||
          (v is num && k == 'f' && v == 0);
      if (emptyVal) {
        r.remove(k);
      } else {
        r[k] = v is String ? v.trim() : v;
      }
    });
    return r;
  }
}
