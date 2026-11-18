// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a uk locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'uk';

  static String m0(site) => "Доступ на ${site}";

  static String m1(version) => "Оновити до ${version}";

  static String m2(n) => "${n} вх.";

  static String m3(example) =>
      "Префікс ключа, під яким агент може пропонувати зміни, повністю: ${example}.";

  static String m4(n) => "${n} д тому";

  static String m5(n) => "${n} год тому";

  static String m6(n) => "${n} хв тому";

  static String m7(code) => "HTTP ${code}";

  static String m8(path, expected, got) =>
      "не шлюз WYRM: ${path}: очікувалось ${expected}, отримано ${got}";

  static String m9(id) => "невідомо: потрібен config на sys/links/${id}";

  static String m10(count) =>
      "${Intl.plural(count, one: 'Застосувати 1 зміну', few: 'Застосувати ${count} зміни', other: 'Застосувати ${count} змін')}";

  static String m11(n) =>
      "${Intl.plural(n, one: '1 крок без позначки змінює щось і виконується власним ключем агента; його не можна пропустити. Щоб зупинити його, відхиліть план.', few: '${n} кроки без позначки змінюють щось і виконуються власним ключем агента; їх не можна пропустити. Щоб зупинити їх, відхиліть план.', other: '${n} кроків без позначки змінюють щось і виконуються власним ключем агента; їх не можна пропустити. Щоб зупинити їх, відхиліть план.')}";

  static String m12(n) =>
      "${Intl.plural(n, one: 'Схвалити 1 зміну й запустити', few: 'Схвалити ${n} зміни й запустити', other: 'Схвалити ${n} змін і запустити')}";

  static String m13(site) =>
      "Це завдання на сайті ${site}. Цей шлюз підписує схвалення лише для завдань власного сайту. Схваліть його через шлюз сайту ${site}.";

  static String m14(why) => "Схвалення відхилено; завдання ще чекає. ${why}";

  static String m15(n) =>
      "Спершу покажіть аргументи кроку ${n}: його схема невідома, тому їх приховано.";

  static String m16(role) =>
      "Підписує один токен на кожен позначений крок з вашими правами (${role}). Непозначені кроки пропускаються.";

  static String m17(count) => "Попросити адміністратора: ${count}";

  static String m18(n) => "просить приєднатися · ретранслює ${n}";

  static String m19(sites) => "просить ретранслювати: ${sites}";

  static String m20(code) => "відмовлено (${code})";

  static String m21(id) =>
      "Лінк ${id} уже є на цьому брокері: його буде замінено на місці (той самий драйвер і режим), спершу створюється його точка відновлення.";

  static String m22(size, rights) => "Близько ${size} · ${rights}";

  static String m23(days) =>
      "Створюються під час роботи брокера і зберігаються на ньому ${days} днів. Завантажте копію або надішліть у файлове сховище.";

  static String m24(name) => "Виберіть теку для ${name}";

  static String m25(link) => "Створити копію ${link}";

  static String m26(when) =>
      "Зберігається на брокері до ${when} (резервні копії).";

  static String m27(done, size) => "Завантаження: ${done} з ${size}";

  static String m28(what) => "Копію ${what} не створено";

  static String m29(site) =>
      "У ній ключі сайту: хто має файл і парольну фразу, той адміністратор ${site}.";

  static String m30(link) => "лінк ${link}";

  static String m31(n) => "Щонайменше ${n} символів";

  static String m32(what) => "Створення копії ${what}";

  static String m33(name) => "Видалити ${name}?";

  static String m34(percent) => "створюється · ${percent} %";

  static String m35(percent) => "надсилається · ${percent} %";

  static String m36(name) => "Збережено ${name}";

  static String m37(size, n) => "${size} · секцій: ${n}";

  static String m38(path) => "Збережено до ${path}; SHA-256 перевірено.";

  static String m39(site) =>
      "запечатано для ${site}: відкривається лише на брокері з його ключами";

  static String m40(error) => "Не надіслано: ${error}";

  static String m41(to) => "Надсилання до ${to}";

  static String m42(link) =>
      "Один файл .wyrm-link з усім, що потрібно ${link} для повернення тут або на іншому брокері.";

  static String m43(site) => "Резервна копія ${site}";

  static String m44(link) => "Резервна копія лінка ${link}";

  static String m45(days) => "Зберігається в резервних копіях ${days} днів.";

  static String m46(days) =>
      "Завантажується частинами, коли готова; також зберігається на брокері ${days} днів.";

  static String m47(n) =>
      "${Intl.plural(n, one: '${n} блок', few: '${n} блоки', other: '${n} блоків')}";

  static String m48(brokers, devices) =>
      "${brokers} брокерів · ${devices} пристроїв";

  static String m49(driver) => "вбудований драйвер ${driver}";

  static String m50(version) => "Знову на ${version}";

  static String m51(tried, version) =>
      "${tried} не пройшла пробний старт. Наступний старт повернув ${version} і відновив площину керування з копії перед оновленням.";

  static String m52(version, latest) => "${version} · доступна ${latest}";

  static String m53(version) => "${version} · актуальна";

  static String m54(version) => "${version} · оновлення відкочено";

  static String m55(version) => "${version} на випробуванні";

  static String m56(version) =>
      "Якщо нова версія записує новішу SCHEMA, ${version} потім її не прочитає: відкат відновлює копію площини керування, зроблену перед оновленням, тож зміни після оновлення втрачаються.";

  static String m57(from, to) => "Зупинено на ${from}, запущено на ${to}";

  static String m58(version) => "${version} підготовлено";

  static String m59(back, all, seconds) => "${back} з ${all} за ${seconds} с";

  static String m60(time) =>
      "Studio втратила шлюз і пробує знову самостійно · ${time}";

  static String m61(version) => "Відкрити журнал ${version}";

  static String m62(site, version) => "${site} перезапускається на ${version}";

  static String m63(site, version) => "Відкотити ${site} до ${version}?";

  static String m64(when) => "можливий до ${when}";

  static String m65(site, version) => "${site} працює на ${version}";

  static String m66(version) =>
      "Оновлення підтверджено; ${version} і копія перед оновленням зберігаються для відкату.";

  static String m67(n) => "${n} с";

  static String m68(version) =>
      "Новий бінарник розміщується поруч із поточним; ${version} залишається на диску.";

  static String m69(version) =>
      "Брокер чисто зупиняється, і менеджер служб запускає ${version} (приблизно 5–15 с без брокера).";

  static String m70(version) =>
      "${version} працює на випробуванні: за 3 хв мають повернутися роутер, шлюз і його лінки.";

  static String m71(version) =>
      "Потім він підтверджує себе. Якщо ні, наступний старт повертає ${version} з копією з кроку 1.";

  static String m72(site, version) => "Оновити ${site} до wyrmd ${version}";

  static String m73(site) => "Введіть ${site} для підтвердження";

  static String m74(site) => "${site} оновлено";

  static String m75(site) => "Оновлення ${site}";

  static String m76(site) => "підписано CA · ${site} CA";

  static String m77(title) => "${title} (процес)";

  static String m78(n) =>
      "${Intl.plural(n, one: '1 блок стає', few: '${n} блоки стають', other: '${n} блоків стають')} одним блоком цього флоу. Дроти, що перетинають його межу, стають його входами та виходами.";

  static String m79(n) =>
      "${Intl.plural(n, zero: 'нічого · його здогад', one: '1 зміна · його здогад', few: '${n} зміни · його здогад', other: '${n} змін · його здогад')}";

  static String m80(count) =>
      "${Intl.plural(count, zero: 'без дочірніх вузлів', one: '${count} дочірній вузол', few: '${count} дочірні вузли', other: '${count} дочірніх вузлів')}";

  static String m81(answer) => "з картки: ${answer}";

  static String m82(answer) => "своїми словами: ${answer}";

  static String m83(site) =>
      "${site} під’єднується до нього; там авторизують ${site}.";

  static String m84(size) => "data_dir ${size}";

  static String m85(id) => "Відкликати допуск ${id}?";

  static String m86(flow) =>
      "Чернетка «${flow}» замінить версію, що працює зараз.";

  static String m87(who) => "розгорнув ${who}";

  static String m88(name) => "Забути ${name}?";

  static String m89(method, when) => "${method} · ${when}";

  static String m90(user) =>
      "${user} більше не зможе відмикати ним; лише вхід з паролем. Запис лишається як видалений вами, доки його не забудуть.";

  static String m91(name) => "Видалити ${name}?";

  static String m92(n, where) =>
      "${Intl.plural(n, one: '${n} gateway у ${where} · оголошено через DNS-SD', few: '${n} gateway у ${where} · оголошено через DNS-SD', other: '${n} gateway у ${where} · оголошено через DNS-SD')}";

  static String m93(where) => "Пошук у ${where}…";

  static String m94(where) => "За 8 с у ${where} не відповів жоден gateway";

  static String m95(n, range) =>
      "${Intl.plural(n, one: '${n} gateway у ${range} · знайдено перевіркою діапазону', few: '${n} gateway у ${range} · знайдено перевіркою діапазону', other: '${n} gateway у ${range} · знайдено перевіркою діапазону')}";

  static String m96(range, port) => "Перевірка ${range} на порту ${port}…";

  static String m97(steps) =>
      "Завдання виконано. Пропущені кроки: ${steps}. Попросіть їх окремим завданням; його план схвалюють окремо.";

  static String m98(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m99(id) => "Параметри ${id}";

  static String m100(time) =>
      "Решта подробиць у журналі брокера близько ${time}.";

  static String m101(field) =>
      "У формі поле ${field} позначено; виправте його та надішліть знову.";

  static String m102(role, site) =>
      "Ваша роль: ${role}. На ${site} нічого не змінено.";

  static String m103(got, expected) =>
      "Отриманий файл — не резервна копія: SHA-256 ${got}, брокер каже ${expected}. Нічого не збережено.";

  static String m104(call, key) => "${call} на ${key}";

  static String m105(type) => "studio · ${type}";

  static String m106(label, value) => "${label}: ${value}";

  static String m107(thing) => "розгорнути ${thing}";

  static String m108(thing) => "встановити ${thing}";

  static String m109(thing) => "отримати список ${thing}";

  static String m110(thing) => "увійти до ${thing}";

  static String m111(thing) => "відкрити ${thing}";

  static String m112(thing) => "прочитати ${thing}";

  static String m113(thing) => "вилучити ${thing}";

  static String m114(call, thing) => "виконати ${call} на ${thing}";

  static String m115(thing) => "зберегти ${thing}";

  static String m116(thing) => "запустити ${thing}";

  static String m117(step) => "завершити «${step}»";

  static String m118(thing) => "зупинити ${thing}";

  static String m119(thing) => "записати ${thing}";

  static String m120(thing) => "Розгортання ${thing}";

  static String m121(thing) => "Встановлення ${thing}";

  static String m122(thing) => "Список ${thing}";

  static String m123(thing) => "Вхід до ${thing}";

  static String m124(thing) => "Відкриття ${thing}";

  static String m125(thing) => "Читання ${thing}";

  static String m126(thing) => "Вилучення ${thing}";

  static String m127(call, thing) => "${call} на ${thing}";

  static String m128(thing) => "Збереження ${thing}";

  static String m129(thing) => "Запуск ${thing}";

  static String m130(thing) => "Зупинка ${thing}";

  static String m131(thing) => "Запис ${thing}";

  static String m132(offset, size) =>
      "Файл закінчився на ${offset} з ${size} байтів.";

  static String m133(flow, why) =>
      "Визначення флоу ${flow} не те, яке читає Studio: ${why}.";

  static String m134(name, field, reason) =>
      "Блок бібліотеки ${name} не той, який читає Studio: ${field}: ${reason}.";

  static String m135(platform) => "На ${platform} немає ключа пристрою.";

  static String m136(call) => "${call}";

  static String m137(name) => "Жоден лінк не запускає пакет ${name}.";

  static String m138(detail) => "Це не JSON: ${detail}";

  static String m139(key, known) =>
      "Невідомий ключ \"${key}\" (відомі: ${known}).";

  static String m140(type) => "Невідомий тип \"${type}\".";

  static String m141(site) => "Брокер на ${site} не відповів.";

  static String m142(status) => "Брокер відповів ${status} без повідомлення.";

  static String m143(status, message) => "${status}: ${message}";

  static String m144(task, field, reason) =>
      "Запис завдання ${task} не той, який читає Studio: ${field}: ${reason}.";

  static String m145(id) => "пристрій ${id}";

  static String m146(time) => "${time} (місцевий)";

  static String m147(doing, site) => "${doing}: помилка на ${site}";

  static String m148(doing) => "${doing}: помилка";

  static String m149(site, what) => "${site} зайнятий: ${what} не почато";

  static String m150(thing) => "${thing} більше немає";

  static String m151(thing) => "Історія ${thing} недоступна";

  static String m152(site) => "${site} не відповідає";

  static String m153(thing) => "Не вдалося прочитати ${thing}";

  static String m154(what) => "Ви не можете ${what}";

  static String m155(site) => "Живі значення з ${site} зупинилися";

  static String m156(what) => "Studio не вдалося ${what}";

  static String m157(thing, call) => "${thing} не підтримує ${call}";

  static String m158(seconds) => "Ще раз через ${seconds} с";

  static String m159(user, role) => "${user} (${role})";

  static String m160(s) => "кожні ${s} с";

  static String m161(version) => "v${version}";

  static String m162(reason) =>
      "Нечитаний файл не вдалося відкласти: ${reason}";

  static String m163(name) =>
      "Нечитаний файл лишиться поруч із новим як ${name}. Ви знову додасте свої gateway та увійдете.";

  static String m164(panel) => "Studio не вдалося намалювати: ${panel}";

  static String m165(panel) => "Не вдалося намалювати: ${panel}";

  static String m166(word, n) => "${word} ${n}";

  static String m167(when) => "уперше ${when}";

  static String m168(mode) =>
      "замінює цей план; з require_approval «${mode}» кроки запису нового плану виконуються без людини";

  static String m169(v) => "v${v} розгорнуто";

  static String m170(v) => "v${v} · помилка";

  static String m171(v) => "v${v} зупинено";

  static String m172(v) => "Версія ${v}";

  static String m173(site) => "Потоки на ${site}";

  static String m174(count) => "Блоків: ${count}";

  static String m175(label) => "Відкріпити «${label}» від блока";

  static String m176(task, steps) =>
      "Виконай кроки, пропущені в плані завдання ${task}: ${steps}.";

  static String m177(n) =>
      "${n} не записано: ваші права вже сплили. Вони діють 5 хв після вашого останнього виклику в цій задачі; хід після запуску їх не поновлює.";

  static String m178(n) => "${n} не записано: це не ключ вузла.";

  static String m179(n) => "${n} не записано: задача тримає не більше 12.";

  static String m180(n) =>
      "${n} не записано: поза тим, що можете читати ви або агент.";

  static String m181(n) =>
      "${n} не записано: ваші права не були відомі (агент перезапустився, або запит їх не мав).";

  static String m182(address) => "з ${address}";

  static String m183(host, ms) => "${host} · відповів за ${ms} мс";

  static String m184(host) => "Немає відповіді від ${host}";

  static String m185(key) => "Перейти до ${key}";

  static String m186(id) => "Доступ для ${id}";

  static String m187(node) => "Розкажіть, що знаєте про ${node}…";

  static String m188(days) => "сирі дані ${days} д";

  static String m189(n) => "${n} рядів";

  static String m190(size) => "Історик ${size}";

  static String m191(id) => "Історія параметрів ${id}";

  static String m192(status) =>
      "Не вдалося прочитати історію: ${status}. Подробиці в «Проблемах».";

  static String m193(main, standby) => "${main} · резерв ${standby}";

  static String m194(n) =>
      "${Intl.plural(n, one: '1 вхід', few: '${n} входи', other: '${n} входів')}";

  static String m195(name, broker) => "${name} встановлено на ${broker}.";

  static String m196(n) =>
      "${Intl.plural(n, zero: 'у цьому флоу немає екземплярів', one: '1 екземпляр у цьому флоу', few: '${n} екземпляри в цьому флоу', other: '${n} екземплярів у цьому флоу')} · зміна тут змінює всі";

  static String m197(count) => "Скопійовано ключів: ${count}";

  static String m198(lag) => "відставання ${lag}";

  static String m199(time) => "останнє читання ${time}";

  static String m200(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m201(n) =>
      "${Intl.plural(n, one: '${n} лінк', few: '${n} лінки', other: '${n} лінків')}";

  static String m202(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m203(site) => "Лінки на ${site}";

  static String m204(first, last) => "${first} і ${last}";

  static String m205(status) =>
      "Не вдалося прочитати список дочірніх вузлів: ${status}. Подробиці в «Проблемах».";

  static String m206(n) =>
      "${Intl.plural(n, one: '1 зміна чекає в «Переглянути і застосувати»; її збережено.', few: '${n} зміни чекають у «Переглянути і застосувати»; їх збережено.', other: '${n} змін чекають у «Переглянути і застосувати»; їх збережено.')}";

  static String m207(reason) => "Шлюз відмовив: ${reason}.";

  static String m208(user, site, min) =>
      "${user} на ${site} · заблоковано після ${min} хв без дій. Значення і дерево приховано; лінки, потоки і сесія працюють далі.";

  static String m209(id) => "Журнал ${id}";

  static String m210(n) =>
      "${Intl.plural(n, one: 'його вживає 1 екземпляр', few: 'його вживають ${n} екземпляри', other: 'його вживають ${n} екземплярів')}";

  static String m211(n) => "бібліотека v${n}";

  static String m212(n) => "вжито: ${n}";

  static String m213(n) => "v${n}";

  static String m214(kind, count) => "${kind} · дій: ${count}";

  static String m215(status) =>
      "Не вдалося прочитати опис: ${status}. Подробиці в «Проблемах».";

  static String m216(n) =>
      "${Intl.plural(n, zero: 'Скласти план', one: 'Скласти план для 1 пристрою', few: 'Скласти план для ${n} пристроїв', other: 'Скласти план для ${n} пристроїв')}";

  static String m217(count) =>
      "${Intl.plural(count, one: '… ще ${count} байт', few: '… ще ${count} байти', other: '… ще ${count} байтів')}";

  static String m218(count) =>
      "${Intl.plural(count, one: 'ще ${count} рядок', few: 'ще ${count} рядки', other: 'ще ${count} рядків')}";

  static String m219(count) => "Вибрано: ${count}";

  static String m220(level, path) => "потрібен рівень ${level} на ${path}";

  static String m221(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m222(level) => "Потрібно ${level} · у вас є";

  static String m223(action) => "Цей вузол не має дії ${action}.";

  static String m224(param) => "Драйвер не має параметра ${param}.";

  static String m225(site) => "немає: ${site} — вершина";

  static String m226(site) => "підписано CA сайту ${site} (відомий)";

  static String m227(site) => "сертифікат CA сайту ${site}, закріплено";

  static String m228(version) => "wyrmd ${version}";

  static String m229(site) => "Дерево покаже wy/${site}.";

  static String m230(node) => "Відкрити ${node} в Explorer";

  static String m231(id) => "Відкрити tasks/${id}";

  static String m232(site) => "Відкриваємо дерево сайту ${site}…";

  static String m233(name) => "пакет ${name}";

  static String m234(n) =>
      "${Intl.plural(n, one: '1 випадок', few: '${n} випадки', other: '${n} випадків')}";

  static String m235(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m236(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m237(detail) => "Це не JSON: ${detail}";

  static String m238(n) =>
      "Додано ${n} ключів, найбільше для одного запиту. Спершу приберіть один.";

  static String m239(site) =>
      "Додайте вузол ${site} як @-чип: фільтруйте або введіть його ключ";

  static String m240(key) => "${key} поза тим, що агент може читати";

  static String m241(key) => "Додати ${key}";

  static String m242(site) => "${site} · вибрано в цій мережі";

  static String m243(site) =>
      "${site} · вибрано в цій мережі · резерв заповнено";

  static String m244(now, atRun) =>
      "чекає на схвалення · перевірено зараз: ${now}, під час виконання: ${atRun}";

  static String m245(n) => "потребує кроку ${n}";

  static String m246(path) =>
      "Збережено ${path}. Запустіть його через wyrm-agent run.";

  static String m247(steps) =>
      "Секретних аргументів у файлі немає: ${steps}. Додайте їх перед запуском.";

  static String m248(n, names) => "крок ${n}: ${names}";

  static String m249(s) => "${s} с";

  static String m250(n) =>
      "${Intl.plural(n, one: 'План · ${n} крок', few: 'План · ${n} кроки', many: 'План · ${n} кроків', other: 'План · ${n} кроку')}";

  static String m251(s) => "тайм-аут ${s} с";

  static String m252(n) =>
      "${Intl.plural(n, one: '${n} точка', few: '${n} точки', other: '${n} точок')}";

  static String m253(n) =>
      "${Intl.plural(n, one: '1 порт', few: '${n} порти', other: '${n} портів')}";

  static String m254(step) => "${step} · пізніше";

  static String m255(site) => "Читання дерева сайту ${site}";

  static String m256(message) => "Чернетка не запускається: ${message}";

  static String m257(reason) =>
      "Недоступно: /api/info не відповів (${reason}).";

  static String m258(version) =>
      "Недоступно: цьому gateway потрібна Studio ${version} або новіша.";

  static String m259(count) =>
      "${Intl.plural(count, one: '1 проблема', few: '${count} проблеми', many: '${count} проблем', other: '${count} проблеми')}";

  static String m260(name) => "${name} встановлено";

  static String m261(name) => "Встановлення ${name}…";

  static String m262(sites) => "досягає ${sites}";

  static String m263(status) =>
      "Не вдалося прочитати значення: ${status}. Подробиці в «Проблемах».";

  static String m264(field) =>
      "Цей брокер не може прив\'язати ${field} (його рушій флоу старший за ADR 0040)";

  static String m265(field) => "${field} не має входу: введіть значення";

  static String m266(from, to) => "${from} не підходить до ${to}";

  static String m267(cn) => "Відхилити ${cn}?";

  static String m268(n) =>
      "${Intl.plural(n, one: 'ретранслює ${n} сайт', few: 'ретранслює ${n} сайти', other: 'ретранслює ${n} сайтів')}";

  static String m269(id) => "Видалити ${id}?";

  static String m270(name) => "Видалити ${name}?";

  static String m271(id) =>
      "Цей план замінило завдання tasks/${id}, і його не можна схвалити. Схваліть план того завдання.";

  static String m272(action) => "Результат · ${action}";

  static String m273(what) => "повертає ${what}";

  static String m274(audit) =>
      "Кожен запис перевіряє лінк і фіксує в ${audit}. Значення зʼявляється лише після зворотного читання.";

  static String m275(rev) => "Ревізія ${rev}";

  static String m276(rev) => "Ревізія ${rev} · діє";

  static String m277(n) => "${n} MiB";

  static String m278(n) => "${n} мс";

  static String m279(path) => "на ${path}";

  static String m280(site, user, role, level) =>
      "Сайт ${site} · застосовується з вашими правами: ${user}, ${role} (${level})";

  static String m281(role, site) => "${role} на ${site}";

  static String m282(rev) => "Повернути ревізію ${rev}?";

  static String m283(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m284(site, broker) => "З ${site} · wyrmd ${broker}";

  static String m285(when, n, sealed) =>
      "Створено ${when} · секцій: ${n} · секрети: ${sealed}";

  static String m286(fresh, exists) =>
      "Лінки: нових ${fresh}, наявних тут ${exists}";

  static String m287(site) => "Копія іншого сайту: ${site}";

  static String m288(files) => "Замінити ключі сайту: ${files}";

  static String m289(site) => "${site} перезапускається і застосовує копію";

  static String m290(site) => "Відновити ${site} з резервної копії";

  static String m291(done, size) => "Вивантаження: ${done} з ${size}";

  static String m292(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m293(s) => "усі кроки пройшли · ${s} с";

  static String m294(steps) => "виконано · пропущені кроки: ${steps}";

  static String m295(steps) =>
      "зупинено · кроки ${steps} щось змінили й лишаються виконаними";

  static String m296(n) =>
      "зупинено · крок ${n} щось змінив і лишається виконаним";

  static String m297(n, of) => "Виконання · крок ${n} з ${of}";

  static String m298(of) => "Виконання · кроків: ${of}";

  static String m299(site) => "Працює на ${site}";

  static String m300(task) => "Зберегти план завдання ${task}";

  static String m301(name) => "${name}";

  static String m302(date) => "додано ${date}";

  static String m303(site) =>
      "Встановлено ${site} (gateway.devices.step_up: config); тут це не вимкнути.";

  static String m304(site) =>
      "${site} цього не просить (gateway.devices.step_up: none); увімкнути може лише шлюз.";

  static String m305(site) => "Ваші пристрої на ${site}";

  static String m306(n) =>
      "${Intl.plural(n, zero: 'пароль потрібен сьогодні', one: 'пароль потрібен за 1 день', few: 'пароль потрібен за ${n} дні', other: 'пароль потрібен за ${n} днів')}";

  static String m307(site, max) =>
      "Приховує дерево і значення; сесію і «Переглянути і застосувати» збережено. ${site} дозволяє щонайбільше ${max} хв.";

  static String m308(n) => "${n} хв";

  static String m309(device) => "На ${device}";

  static String m310(site) => "${site} просить ваш пароль перед новим ключем.";

  static String m311(site, state, max, days, confirm) =>
      "Політика ${site}: пристрої ${state} · до ${max} · пароль кожні ${days} днів${confirm}. Адміністратор бачить і видаляє пристрої в Доступ › Користувачі.";

  static String m312(admin) => "видалив ${admin}";

  static String m313(user) =>
      "Усі сесії й усі пристрої ${user} завершуються, цей теж.";

  static String m314(store, date, device) =>
      "Ключ у ${store}, додано ${date}. Вимкнення видаляє ключ тут і ${device} з ваших пристроїв.";

  static String m315(store) =>
      "Вимкнено: Studio тут питає пароль. Увімкнення створює ключ у ${store}.";

  static String m316(s) => "${s} с";

  static String m317(level) => "Рівень журналу ${level}";

  static String m318(site) => "Сайти навколо ${site}";

  static String m319(site) =>
      "До чого під’єднаний ${site} і що під’єднано до нього: брокери вище й нижче, платформи, куди він надсилає, і пристрої, чиї лінки працюють поза брокером.";

  static String m320(count) =>
      "${Intl.plural(count, one: '${count} байт', few: '${count} байти', other: '${count} байтів')}";

  static String m321(count) =>
      "${Intl.plural(count, one: '${count} символ', few: '${count} символи', other: '${count} символів')}";

  static String m322(count) =>
      "${Intl.plural(count, one: '${count} стовпець', few: '${count} стовпці', other: '${count} стовпців')}";

  static String m323(count) =>
      "${Intl.plural(count, one: '${count} елемент', few: '${count} елементи', other: '${count} елементів')}";

  static String m324(count) =>
      "${Intl.plural(count, one: '${count} ключ', few: '${count} ключі', other: '${count} ключів')}";

  static String m325(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m326(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m327(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m328(was) => "підготовлено · було ${was}";

  static String m329(host) => "Резерв: ${host}";

  static String m330(n, total) => "Крок ${n} з ${total}";

  static String m331(host) => "З’єднання з ${host}";

  static String m332(n) => "пропущено: потрібен крок ${n}";

  static String m333(name) => "Підтвердити через ${name}";

  static String m334(name, site, device) =>
      "${name} підписує лише цей запит: ${site} отримує доказ, прив’язаний до цих змін, і лишається підтвердженим на ${device} 5 хвилин.";

  static String m335(site) =>
      "${site} не прийняв підтвердження: ключ більше не відкривається";

  static String m336(n, site) =>
      "${Intl.plural(n, one: 'Застосувати 1 зміну на ${site}.', few: 'Застосувати ${n} зміни на ${site}.', other: 'Застосувати ${n} змін на ${site}.')} ${site} просить свіже підтвердження перед змінами рівня config.";

  static String m337(site) =>
      "Введіть пароль: ${site} лишається підтвердженим 5 хвилин.";

  static String m338(site, reason) =>
      "${site} не прийняв підтвердження: ${reason}";

  static String m339(name) =>
      "${name} не підтвердив. Спробуйте ще раз або введіть пароль.";

  static String m340(name) => "Очікування ${name}…";

  static String m341(n) => "Зупинено на кроці ${n}";

  static String m342(n, code) => "Зупинено на кроці ${n} · ${code}";

  static String m343(why) =>
      "${why}\nЗроблене до нього лишається; ніщо не скасовується само.";

  static String m344(version, os) => "${version} (${os})";

  static String m345(version, language) => "Studio ${version} · ${language}";

  static String m346(n) => "Відмов ACL побільшало на ${n}";

  static String m347(from) =>
      "acl_denied дорівнював ${from}, коли цей екран показували востаннє";

  static String m348(n) => "Резерв відстає на ${n} записів";

  static String m349(n) => "Відкладено розгалужень після розколу: ${n}";

  static String m350(site) => "${site} чекає на Authorize";

  static String m351(n) => "Нижчий брокер, що ретранслює сайтів: ${n}";

  static String m352(id) =>
      "sys/links/${id}/state має стан failed; причина в його журналі";

  static String m353(id) => "${id} не працює";

  static String m354(cn) => "${cn} чекає в карантині";

  static String m355(cn) => "Невідомий сертифікат CN ${cn}";

  static String m356(cn, t) => "Невідомий сертифікат CN ${cn} від ${t}";

  static String m357(size) =>
      "Усе, чим володіє брокер, лежить у його `data_dir` (тут ${size}). Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:";

  static String m358(n) =>
      "Наборів записів, відкладених після того, як обидва брокери були активні (усунений розкол): ${n}. Запис аудиту `standby_forked` каже які.";

  static String m359(n) =>
      "Записів реєстру, яких ще немає на резерві: ${n}. Перемикання зараз їх втратить.";

  static String m360(n) => "Очистити від’єднані лінки (${n})…";

  static String m361(ids) =>
      "${ids}\n\nЇхні id вибувають і більше не можуть бути використані.";

  static String m362(n) => "Очистити від’єднані лінки: ${n}…";

  static String m363(ids) => "Вилучено: ${ids}";

  static String m364(title) => "Копіювати: ${title}";

  static String m365(url) => "Посилання на посібник скопійовано: ${url}";

  static String m366(id) => "лінк: ${id}";

  static String m367(n) => "Скопійовано рядків: ${n}";

  static String m368(detail) => "Відповідь не є журналом (${detail}).";

  static String m369(path) => "Збережено ${path}";

  static String m370(n) =>
      "Рядків із кільця брокера: ${n} · новіші зверху · `sys/~act/get_log`";

  static String m371(n, m, time) =>
      "Рядків у межах 2 хв від ${time} UTC: ${n} з ${m} · новіші зверху · `sys/~act/get_log`";

  static String m372(t) => "запущено ${t}";

  static String m373(n) => "Потребує уваги · ${n}";

  static String m374(m, time) =>
      "Серед найновіших ${m} рядків немає жодного в межах 2 хв від ${time} UTC. Запитайте більше рядків або очистьте час.";

  static String m375(standby) =>
      "2. У `wyrmd.json5` на обох хостах: `${standby}` і `peers.listen`; радимо `arbiter` оренди на третьому хості.";

  static String m376(t) => "${t} · зараз";

  static String m377(n) => "з ${n}";

  static String m378(name) =>
      "Файл ${name}. Файл .cbor надсилається як є; файл JSON спершу кодується.";

  static String m379(name) => "Профіль ${name} додано";

  static String m380(name) => "Профіль ${name} вилучено";

  static String m381(reason) =>
      "Цей брокер не віддає перелік профілів через шлюз (${reason}). Профіль усе одно можна додати; брокер віддаватиме його як pub/<name>.";

  static String m382(name) => "Вилучити профіль ${name}";

  static String m383(name) =>
      "Брокер перестає віддавати pub/${name} і записує це в журнал аудиту (profile_remove).";

  static String m384(cn) => "зовнішній · CN ${cn}";

  static String m385(size) => "історія ${size} · відкрити Історію";

  static String m386(id) => "${id} не працює · відкрити Лінки";

  static String m387(site) => "${site} · відкрити Сайти";

  static String m388(cn) => "${cn} чекає · відкрити Карантин";

  static String m389(measure, from, to) =>
      "${measure} на вхід і вихід за секунду від ${from} до ${to}";

  static String m390(shown, total) => "${shown} з ${total} рядків";

  static String m391(up) => "нижче ${up}";

  static String m392(level) => "потрібно ${level}";

  static String m393(who) => "від ${who}";

  static String m394(n) => "помилка на кроці ${n}";

  static String m395(agent) => "Кожна задача — вузол: ${agent}/tasks/<id>";

  static String m396(id) => "замінено на ${id}";

  static String m397(who, op, key) => "${who} · ${op} ${key}";

  static String m398(point, range) => "${point} · останні ${range}";

  static String m399(site) => "TLS · сертифікат CA сайту ${site}";

  static String m400(site) => "TLS · CA сайту ${site}, ще не довірено";

  static String m401(site) =>
      "TLS · CA сайту ${site}, закріплено на цьому комп’ютері";

  static String m402(seconds) => "зникне через ${seconds} с";

  static String m403(site) => "лишається, доки ${site} не повернеться";

  static String m404(used, budget) => "${used} з ${budget} токенів";

  static String m405(site) => "Дерево · ${site}";

  static String m406(step) => "середнє за ${step}";

  static String m407(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m408(at, delta, key, over) =>
      "Δ від A (${at}): ${delta} ${key} за ${over}";

  static String m409(what, range) =>
      "${what}, ${range}. Виберіть діапазон вікном нижче.";

  static String m410(h, m) => "${h} год ${m} хв";

  static String m411(key) => "Ви не можете читати ${key}";

  static String m412(t) => "A · ${t}";

  static String m413(min, max) => "мін ${min} · макс ${max}";

  static String m414(m) => "${m} хв";

  static String m415(point) => "Тренд ${point}";

  static String m416(t) => "сирі · ${t}";

  static String m417(s) => "${s} с";

  static String m418(name) => "Показати або сховати ${name}";

  static String m419(n) => "${n} д";

  static String m420(n) => "${n} год";

  static String m421(n) => "${n} хв";

  static String m422(site) => "Збігається · довіряти ${site}";

  static String m423(host) =>
      "Сертифікат gateway не підписано цим CA, або він не називає ${host}. Нічому не довірено.";

  static String m424(site) => "Вперше на ${site} · перевірте сертифікат";

  static String m425(command) =>
      "На брокері: System › Gateway › Certificate code, або ${command} на його хості.";

  static String m426(site) =>
      "Gateway сайту ${site} має власний CA, якого цей комп’ютер не знає. Порівняйте код із кодом на брокері, перш ніж довіряти: будь-хто в цій мережі може оголосити ім’я.";

  static String m427(unit) => "адреса ${unit}";

  static String m428(name) => "${name} не відкрив ключ";

  static String m429(device) =>
      "Обличчя на ${device} змінилися, тож ключ, який зберігав Studio, більше не відкривається. Людина з новим обличчям не ввійде як ви.";

  static String m430(device) =>
      "Відбитки пальців на ${device} змінилися, тож ключ, який зберігав Studio, більше не відкривається. Людина з новим відбитком не ввійде як ви.";

  static String m431(name) => "${name} вимкнено для цього облікового запису";

  static String m432(site) => "Перевірка ключа на ${site}…";

  static String m433(site) => "підтвердити зміни на ${site}";

  static String m434(days, name) =>
      "Від останнього пароля тут минуло ${days} днів. Після цього входу ${name} знову працює.";

  static String m435(site, days) => "${site} просить пароль кожні ${days} днів";

  static String m436(site, user) => "увімкнути відмикання ${site} як ${user}";

  static String m437(site, days) =>
      "${site} просить пароль раз на ${days} днів.";

  static String m438(site) =>
      "Працює з ${site}. Інші шлюзи просять свій власний.";

  static String m439(site, standby) =>
      "Працює з ${site} і його резервним ${standby}. Інші шлюзи просять свій власний.";

  static String m440(user, site, store) =>
      "Один ключ для ${user} на ${site}, створений у ${store}. Він ніколи звідти не виходить; Studio ніколи не зберігає ваш пароль.";

  static String m441(name) =>
      "Увійдіть з паролем. ${name} лишається ввімкненим на наступний раз.";

  static String m442(store, date) => "Ключ у ${store} · додано ${date}";

  static String m443(name, when) => "${name} · ${when}";

  static String m444(name) => "${name} не збігся 3 рази";

  static String m445(site) => "до шлюзу ${site}.";

  static String m446(site) =>
      "${site} більше не дозволяє біометричне відмикання";

  static String m447(name) => "Не вдалося ввімкнути ${name}";

  static String m448(site, user, role) => "Вхід у ${site} як ${user} · ${role}";

  static String m449(name, site, device) =>
      "Замість пароля ${name} відкриває ключ, який доводить ${site}, що на ${device} саме ви.";

  static String m450(name) => "Наступного разу відмикати через ${name}?";

  static String m451(user) => "Пароль для ${user}";

  static String m452(host) => "${host} + резервний";

  static String m453(site, max) =>
      "${site} це дозволяє: біометричні пристрої увімкнено, до ${max} на користувача (gateway.devices). Вимкнути можна в меню облікового запису › Безпека.";

  static String m454(site, user) => "увійти в ${site} як ${user}";

  static String m455(name) => "Знову ввімкнути ${name} після входу";

  static String m456(device, name) =>
      "Адміністратор видалив ${device} з ваших пристроїв. Увійдіть з паролем; потім можна знову ввімкнути ${name}.";

  static String m457(role, site) => "· ${role} на ${site}";

  static String m458(site) => "Відімкніть, щоб відкрити дерево ${site}.";

  static String m459(device, name) =>
      "Шлюз більше не має запису про ${device}. Увійдіть з паролем; потім можна знову ввімкнути ${name}.";

  static String m460(site) => "${site} не знає цього ключа";

  static String m461(name) => "Використати ${name}";

  static String m462(name) => "Відімкнути через ${name}";

  static String m463(d) => "працює ${d}";

  static String m464(n) => "Оновити лінків: ${n}";

  static String m465(version) => "${version} залишається, лінк не відповів";

  static String m466(package) =>
      "Дайте zip пакета ${package} з вищою версією. Брокер перевіряє його як будь-яке встановлення і оновлює всі лінки пакета.";

  static String m467(links) => "Гарячий старт, без перезапуску: ${links}";

  static String m468(version, when) =>
      "${version} залишається встановленою до ${when}. Точка відновлення запечатана для цього брокера і залишається на ньому.";

  static String m469(n) => "лінків: ${n}";

  static String m470(n, links) => "Лінки, що перезапускаються (${n}): ${links}";

  static String m471(link) => "Відкрити ${link}";

  static String m472(link) => "${link} · перед відновленням з резервної копії";

  static String m473(link, version) =>
      "${link} · ${version} · перед оновленням";

  static String m474(version, links) =>
      "Ці лінки зупиняться і запустяться на ${version}: ${links}. Брокер повертає їхні приватні дані до точки відновлення оновлення, якщо оновлення змінило формат сховища або закінчилося погано; після вдалого оновлення вони зберігають поточні дані. Після цього жодна версія не зберігається: другого відкату немає.";

  static String m475(package, version) => "Відкотити ${package} до ${version}?";

  static String m476(version) => "Відкотити до ${version}…";

  static String m477(version) => "Відкочено до ${version}";

  static String m478(version) => "Лінки працюють на ${version}";

  static String m479(links) => "${links}: повернулися з усіма вузлами.";

  static String m480(state) => "Він змінює формат сховища (зі state ${state})";

  static String m481(state) => "Формат сховища: той самий (state ${state})";

  static String m482(back, gone) =>
      "оголошено знову: ${back} · ще немає або зникло: ${gone}";

  static String m483(n) => "Власний пакет · лінків на ньому: ${n}";

  static String m484(n) => "Пакет репозиторію · лінків на ньому: ${n}";

  static String m485(package, from, to) => "Оновити ${package} ${from} → ${to}";

  static String m486(package, from) => "Оновити ${package} ${from} з файлу";

  static String m487(package) => "${package} оновлено";

  static String m488(package) => "Оновлення ${package} відкочено";

  static String m489(result) => "Брокер завершив його як «${result}»";

  static String m490(package) => "Оновлення ${package}";

  static String m491(package) => "Версії ${package}";

  static String m492(version) => "Що нового у ${version}";

  static String m493(v) => "Версія ${v} · розгорнута";

  static String m494(site) => "через ${site}";

  static String m495(delimiter, header) =>
      "Так, як його читає блок: роздільник ${delimiter}, ${header}";

  static String m496(keys) => "${keys} зберігає · Esc скасовує";

  static String m497(keys) => "${keys} зберігає · Esc відкидає зміни";

  static String m498(n, who) => "${n} чекають на допуск: ${who}";

  static String m499(value) => "було ${value}";

  static String m500(n) => "Групи спостереження · ${n}";

  static String m501(mode) =>
      "З require_approval «${mode}» план вибраного варіанта виконує кроки запису без людини. Мітка — здогад асистента, а не перевірка. Прочитайте плитку, перш ніж вибрати її.";

  static String m502(user) => "Вітаємо, ${user}";

  static String m503(value) => "запустив би на ${value}";

  static String m504(value) => "надіслав би ${value}";

  static String m505(value) => "записав би ${value}";

  static String m506(level) => "Щоб увімкнути, потрібен рівень ${level}";

  static String m507(site) => "wyrmd на ${site}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("uk"),
    "aCustomPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "acceptFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу прийміть запитані права.",
    ),
    "acceptRequestedRights": MessageLookupByLibrary.simpleMessage(
      "Прийняти запитані права",
    ),
    "accepted": MessageLookupByLibrary.simpleMessage("прийнято"),
    "accessOn": m0,
    "accessSubtitle": MessageLookupByLibrary.simpleMessage(
      "Хто може входити в цей gateway, що доступно кожній ролі і що було зроблено.",
    ),
    "actBackUp": MessageLookupByLibrary.simpleMessage("Резервна копія…"),
    "actBackUpNote": MessageLookupByLibrary.simpleMessage(
      "Один файл із налаштуваннями, приватними даними й пакетом; відновлюйте тут або на іншому брокері.",
    ),
    "actComesWithWyrmd": MessageLookupByLibrary.simpleMessage(
      "Входить до wyrmd",
    ),
    "actComesWithWyrmdNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований драйвер оновлюється разом із брокером.",
    ),
    "actDeauthorize": MessageLookupByLibrary.simpleMessage("Відкликати допуск"),
    "actDeauthorizeNote": MessageLookupByLibrary.simpleMessage(
      "Заблокувати зараз: права забрано, наступне з’єднання чекатиме в карантині. Дерево лишається.",
    ),
    "actEditParams": MessageLookupByLibrary.simpleMessage("Змінити параметри"),
    "actEditParamsNote": MessageLookupByLibrary.simpleMessage(
      "Параметри лінка. Зберігаються як нова ревізія.",
    ),
    "actGrant": MessageLookupByLibrary.simpleMessage("Надати доступ"),
    "actGrantNote": MessageLookupByLibrary.simpleMessage(
      "Читання або запис поза власною гілкою.",
    ),
    "actGrants": MessageLookupByLibrary.simpleMessage("Доступи"),
    "actGrantsNote": MessageLookupByLibrary.simpleMessage(
      "Лише власна гілка. Додайте читання або запис деінде.",
    ),
    "actParamsHistory": MessageLookupByLibrary.simpleMessage(
      "Історія параметрів",
    ),
    "actParamsHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Ревізії параметрів; поверніться до будь-якої.",
    ),
    "actRemoveForGood": MessageLookupByLibrary.simpleMessage(
      "Видалити назавжди",
    ),
    "actRemoveForGoodNote": MessageLookupByLibrary.simpleMessage(
      "Вилучити id: цей сертифікат більше не отримає прав. Новому пристрою потрібен новий сертифікат.",
    ),
    "actRemoveLink": MessageLookupByLibrary.simpleMessage("Видалити лінк"),
    "actRemoveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Зупиняє його і видаляє його дерево.",
    ),
    "actSecrets": MessageLookupByLibrary.simpleMessage("Секрети"),
    "actSecretsNote": MessageLookupByLibrary.simpleMessage(
      "Паролі й ключі, запечатані; більше не показуються.",
    ),
    "actStart": MessageLookupByLibrary.simpleMessage("Запустити"),
    "actStartNote": MessageLookupByLibrary.simpleMessage(
      "Запустити знову з останніми параметрами.",
    ),
    "actStartStopRestart": MessageLookupByLibrary.simpleMessage(
      "Запуск, зупинка, перезапуск",
    ),
    "actStop": MessageLookupByLibrary.simpleMessage("Зупинити"),
    "actStopNote": MessageLookupByLibrary.simpleMessage(
      "Лишається встановленим; його точки стають bad до запуску.",
    ),
    "actUpdateFromFile": MessageLookupByLibrary.simpleMessage(
      "Оновити з файлу…",
    ),
    "actUpdateFromFileNote": MessageLookupByLibrary.simpleMessage(
      "Власний пакет: дайте його новіший архів.",
    ),
    "actUpdateTo": m1,
    "actUpdateToNote": MessageLookupByLibrary.simpleMessage(
      "У репозиторії є новіша версія його пакета. Спершу перегляньте, що зміниться.",
    ),
    "actUpgrade": MessageLookupByLibrary.simpleMessage("Оновити"),
    "actUpgradeNote": MessageLookupByLibrary.simpleMessage(
      "Встановити новішу версію пакета.",
    ),
    "actUpgradeParamsLog": MessageLookupByLibrary.simpleMessage(
      "Оновлення, параметри, журнал",
    ),
    "actVersions": MessageLookupByLibrary.simpleMessage(
      "Версії і точки відновлення",
    ),
    "actVersionsNote": MessageLookupByLibrary.simpleMessage(
      "Останнє оновлення, точки відновлення цього лінка, відкат до збереженої версії.",
    ),
    "actViewLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "actViewLogNote": MessageLookupByLibrary.simpleMessage(
      "Останні рядки і власний рівень журналу.",
    ),
    "actionInputs": m2,
    "addALink": MessageLookupByLibrary.simpleMessage("Додати лінк"),
    "addAgent": MessageLookupByLibrary.simpleMessage("Додати link агента"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Додати ще"),
    "addFromExplorer": MessageLookupByLibrary.simpleMessage("+ з Explorer"),
    "addFromExplorerNone": MessageLookupByLibrary.simpleMessage(
      "Спершу відкрийте сайт; тоді його вузли можна додати сюди як @-чипи.",
    ),
    "addGrant": MessageLookupByLibrary.simpleMessage("Додати дозвіл"),
    "addInput": MessageLookupByLibrary.simpleMessage("Додати вхід"),
    "addPair": MessageLookupByLibrary.simpleMessage("Додати випадок"),
    "addPoint": MessageLookupByLibrary.simpleMessage("Додати точку"),
    "addPort": MessageLookupByLibrary.simpleMessage("Додати порт"),
    "addPrefix": MessageLookupByLibrary.simpleMessage("+ префікс"),
    "addPrefixButton": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "addPrefixHint": MessageLookupByLibrary.simpleMessage("wy/…"),
    "addPrefixNote": m3,
    "addPrefixTitle": MessageLookupByLibrary.simpleMessage("Додати префікс"),
    "addStandby": MessageLookupByLibrary.simpleMessage(
      "Додати резервний gateway",
    ),
    "addUser": MessageLookupByLibrary.simpleMessage("Додати користувача"),
    "addWatchPath": MessageLookupByLibrary.simpleMessage("Додати точку"),
    "addWatchPathNote": MessageLookupByLibrary.simpleMessage(
      "Записувати ще одну точку (ключ у downstream, dataflows або storage).",
    ),
    "adminsOnly": MessageLookupByLibrary.simpleMessage(
      "Користувачами керують адміністратори gateway.",
    ),
    "agoDays": m4,
    "agoHours": m5,
    "agoMinutes": m6,
    "agoNow": MessageLookupByLibrary.simpleMessage("щойно"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage(
      "Допускати всі лінки",
    ),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Кожен новий CN цього CA одразу стає лінком, без схвалення. Витеклий сертифікат теж пройде.",
    ),
    "andWord": MessageLookupByLibrary.simpleMessage("і"),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "answerButton": MessageLookupByLibrary.simpleMessage("Відповісти"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "answerHint": MessageLookupByLibrary.simpleMessage(
      "Дайте відповідь своїми словами (Cmd+Enter)",
    ),
    "answerHttp": m7,
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerNotGateway": MessageLookupByLibrary.simpleMessage("не шлюз WYRM"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "answerTimedOut": MessageLookupByLibrary.simpleMessage("час вийшов"),
    "answerWaitingNote": MessageLookupByLibrary.simpleMessage(
      "Асистент чекає на вашу відповідь. До неї нічого не планується. Перезапуск брокера завершує завдання, що чекає.",
    ),
    "answerWrongShape": m8,
    "apiKeyNotSet": MessageLookupByLibrary.simpleMessage("не задано"),
    "apiKeySet": MessageLookupByLibrary.simpleMessage(
      "задано · ніколи не показується",
    ),
    "apiKeyUnknown": m9,
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "applyChanges": m10,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Застосувати профіль"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveByAgent": m11,
    "approveCount": m12,
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "approveNone": MessageLookupByLibrary.simpleMessage(
      "Позначте хоча б один крок.",
    ),
    "approveOtherSite": m13,
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення в Studio з\'явиться з наступним кроком. Поки що схвалюй через wyrm-agent.",
    ),
    "approveRefused": m14,
    "approveRefusedHint": MessageLookupByLibrary.simpleMessage(
      "Зніміть позначку з названого кроку й схваліть решту. Коли план виконано, попросіть пропущені кроки окремим завданням: їх схвалюють тоді.",
    ),
    "approveReveal": m15,
    "approveSigns": m16,
    "areaCoil": MessageLookupByLibrary.simpleMessage("Coil"),
    "areaDiscrete": MessageLookupByLibrary.simpleMessage("DI"),
    "areaHolding": MessageLookupByLibrary.simpleMessage("HR"),
    "areaInput": MessageLookupByLibrary.simpleMessage("IR"),
    "argsMasked": MessageLookupByLibrary.simpleMessage(
      "Схема цього кроку ще невідома (його вузол створює попередній крок): аргументи приховано, і жоден не потрапить у збережений план.",
    ),
    "askAdminFor": m17,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має виклику, щоб надіслати запит адміністратору.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Запитати"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну або постав питання про мережу (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("просить приєднатися"),
    "asksToJoinRelays": m18,
    "asksToRelay": m19,
    "auditDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "Аудит потребує рівня config на sys/audit.",
    ),
    "auditRefused": m20,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "backupPassphrase": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза копії",
    ),
    "backupPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Лише для копії, запечатаної парольною фразою. Копія, запечатана для свого сайту, фрази не потребує і відкривається лише на брокері з ключами того сайту. Studio її не зберігає.",
    ),
    "backupReplaces": m21,
    "backupRightsAsk": MessageLookupByLibrary.simpleMessage(
      "брокер запитає за потреби",
    ),
    "backupRightsNote": MessageLookupByLibrary.simpleMessage(
      "Потрібно, коли лінк має права або список дозволених мереж: без цього брокер показує їх і нічого не встановлює. Токен, сертифікат і ключ запитувача будуть нові.",
    ),
    "bakAbout": m22,
    "bakAll": MessageLookupByLibrary.simpleMessage("Усе"),
    "bakBackUp": MessageLookupByLibrary.simpleMessage("Створити копію…"),
    "bakCancelDownload": MessageLookupByLibrary.simpleMessage(
      "Скасувати завантаження",
    ),
    "bakCard": MessageLookupByLibrary.simpleMessage("Резервні копії"),
    "bakCardEmpty": MessageLookupByLibrary.simpleMessage(
      "На брокері немає резервних копій.",
    ),
    "bakCardNote": m23,
    "bakCardOld": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має резервних копій зі Studio (на ньому wyrmd до ADR 0048). Скористайтеся командами нижче.",
    ),
    "bakChooseConnection": MessageLookupByLibrary.simpleMessage(
      "Виберіть лінк і з\'єднання",
    ),
    "bakChooseFolder": m24,
    "bakConsistent": MessageLookupByLibrary.simpleMessage(
      "Кожне сховище читається в один узгоджений момент, у власній транзакції читання; брокер працює і записує далі.",
    ),
    "bakDo": MessageLookupByLibrary.simpleMessage("Створити копію"),
    "bakDoLink": m25,
    "bakDoneSub": m26,
    "bakDoneTitle": MessageLookupByLibrary.simpleMessage(
      "Резервна копія готова",
    ),
    "bakDownload": MessageLookupByLibrary.simpleMessage("Завантажити…"),
    "bakDownloading": m27,
    "bakFactBy": MessageLookupByLibrary.simpleMessage("Створив"),
    "bakFactContents": MessageLookupByLibrary.simpleMessage("Вміст"),
    "bakFactLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "bakFactSealed": MessageLookupByLibrary.simpleMessage("Секрети"),
    "bakFactSent": MessageLookupByLibrary.simpleMessage("Надіслано до"),
    "bakFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер не створив резервну копію",
    ),
    "bakFailedTitle": m28,
    "bakKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Введіть нижче парольну фразу щонайменше з 12 символів: нею запечатуються ключі.",
    ),
    "bakKeysNeverSent": MessageLookupByLibrary.simpleMessage(
      "Резервну копію з ключами й секретами не надсилають: завантажте її на власному шлюзі сайту.",
    ),
    "bakKeysWarning": m29,
    "bakKindFull": MessageLookupByLibrary.simpleMessage("брокер"),
    "bakKindLink": m30,
    "bakKindPreRestore": MessageLookupByLibrary.simpleMessage(
      "перед відновленням",
    ),
    "bakKindPreUpdate": MessageLookupByLibrary.simpleMessage(
      "перед оновленням",
    ),
    "bakLast30": MessageLookupByLibrary.simpleMessage("Останні 30 днів"),
    "bakLast7": MessageLookupByLibrary.simpleMessage("Останні 7 днів"),
    "bakLast90": MessageLookupByLibrary.simpleMessage("Останні 90 днів"),
    "bakLinkRestoreNote": MessageLookupByLibrary.simpleMessage(
      "Відновлюйте через Лінки › Додати лінк › З резервної копії: на цьому брокері (замінює лінк після точки відновлення) або на іншому як новий лінк.",
    ),
    "bakNeedsConfig": MessageLookupByLibrary.simpleMessage("config на sys"),
    "bakNeedsConfigLinks": MessageLookupByLibrary.simpleMessage(
      "config на sys/links",
    ),
    "bakNoBackups": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не створює резервні копії для Studio (wyrmd до ADR 0048).",
    ),
    "bakNoConnections": MessageLookupByLibrary.simpleMessage(
      "Цей лінк не має з\'єднань.",
    ),
    "bakNoSendLinks": MessageLookupByLibrary.simpleMessage(
      "Хост не вказав лінк файлового сховища для резервних копій (backups.send_links у wyrmd.json5).",
    ),
    "bakOffline": MessageLookupByLibrary.simpleMessage(
      "Коли брокер не запускається",
    ),
    "bakOfflineNote": MessageLookupByLibrary.simpleMessage(
      "Офлайн-спосіб для брокера, що не запускається, або хоста без Studio: копія data_dir, зроблена на хості. Кроки, готові до копіювання:",
    ),
    "bakOpen": MessageLookupByLibrary.simpleMessage("Відкрити"),
    "bakPassphrase": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза для ключів і секретів",
    ),
    "bakPassphraseLink": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза для його приватних даних",
    ),
    "bakPassphraseLinkNote": MessageLookupByLibrary.simpleMessage(
      "З нею файл відкривається на будь-якому брокері. Без неї приватні дані запечатуються для цього сайту й відкриваються лише на брокері з його ключами. Studio її не зберігає.",
    ),
    "bakPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Запечатує ключі, секрети й секрети лінків (Argon2id). Без неї ключі не потрапляють у файл, а секрети лінків запечатуються для цього сайту. Studio її не зберігає.",
    ),
    "bakPassphraseShort": m31,
    "bakProgressSub": MessageLookupByLibrary.simpleMessage(
      "Можна закрити; брокер завершить і збереже її в резервних копіях.",
    ),
    "bakProgressTitle": m32,
    "bakRemoveNote": MessageLookupByLibrary.simpleMessage(
      "Файл видаляється з брокера. Завантажена чи надіслана копія залишається.",
    ),
    "bakRemoveRow": MessageLookupByLibrary.simpleMessage(
      "Видалити її з брокера",
    ),
    "bakRemoveTitle": m33,
    "bakRestore": MessageLookupByLibrary.simpleMessage("Відновити…"),
    "bakRowFailed": MessageLookupByLibrary.simpleMessage("помилка"),
    "bakRowRunning": m34,
    "bakRowSending": m35,
    "bakSaved": m36,
    "bakSavedNote": m37,
    "bakSavedTo": m38,
    "bakSealedBroker": m39,
    "bakSealedNone": MessageLookupByLibrary.simpleMessage("у файлі немає"),
    "bakSealedPassphrase": MessageLookupByLibrary.simpleMessage(
      "запечатано парольною фразою",
    ),
    "bakSecConfig": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 (лише читання)",
    ),
    "bakSecConfigNote": MessageLookupByLibrary.simpleMessage(
      "Конфігурація з прихованими секретами, для довідки; відновлення її не записує.",
    ),
    "bakSecControl": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "bakSecControlNote": MessageLookupByLibrary.simpleMessage(
      "Реєстр (лінки, права, сусіди, токени), користувачі й ролі, сховище потоків, аудит. Потрібна для відновлення всього іншого.",
    ),
    "bakSecData": MessageLookupByLibrary.simpleMessage("Приватні дані"),
    "bakSecDataNote": MessageLookupByLibrary.simpleMessage(
      "Його секрети й приватний каталог: зміни драйвера під час роботи (з\'єднання, пристрої, точки), сховище портативного застосунку.",
    ),
    "bakSecDataflows": MessageLookupByLibrary.simpleMessage("Потоки даних"),
    "bakSecDataflowsNote": MessageLookupByLibrary.simpleMessage(
      "Артефакти рушія потоків; самі потоки містяться в площині керування.",
    ),
    "bakSecHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "bakSecHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Записані дні історика та його індекс.",
    ),
    "bakSecKeys": MessageLookupByLibrary.simpleMessage("Ключі й секрети"),
    "bakSecKeysNote": MessageLookupByLibrary.simpleMessage(
      "CA сайту, ключі стану й секретів, ключі шлюзу, токени лінків і запечатані секрети. Запечатуються парольною фразою нижче.",
    ),
    "bakSecLinkHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Записані рядки його точок.",
    ),
    "bakSecLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "bakSecLinksNote": MessageLookupByLibrary.simpleMessage(
      "Для кожного лінка: його визначення, секрети й приватні дані, запечатані. Їхні пакети теж потрапляють у файл.",
    ),
    "bakSecPackage": MessageLookupByLibrary.simpleMessage("Пакет"),
    "bakSecPackageNote": MessageLookupByLibrary.simpleMessage(
      "Пакет, на якому він працює, як файли: відновлення можливе без доступу до репозиторію.",
    ),
    "bakSecPackages": MessageLookupByLibrary.simpleMessage(
      "Встановлені пакети",
    ),
    "bakSecPackagesNote": MessageLookupByLibrary.simpleMessage(
      "Кожен встановлений пакет як файли, тож відновленню не потрібен репозиторій.",
    ),
    "bakSecSettings": MessageLookupByLibrary.simpleMessage("Налаштування"),
    "bakSecSettingsNote": MessageLookupByLibrary.simpleMessage(
      "Визначення лінка: драйвер, режим, параметри, права.",
    ),
    "bakSecStorage": MessageLookupByLibrary.simpleMessage("Сховище брокера"),
    "bakSecStorageNote": MessageLookupByLibrary.simpleMessage(
      "Дерево сховища та його значення, з JSON-експортом для людей.",
    ),
    "bakSecretsHost": MessageLookupByLibrary.simpleMessage(
      "Хост не дозволяє секретам залишати цей брокер (backups.export_secrets у wyrmd.json5 дорівнює false). Секрети запечатуються для цього сайту.",
    ),
    "bakSecretsUpstream": MessageLookupByLibrary.simpleMessage(
      "Ця сесія дістається сайту через вищий брокер: його ключі й файл під парольною фразою не йдуть угору. Увійдіть на власному шлюзі сайту.",
    ),
    "bakSend": MessageLookupByLibrary.simpleMessage("Надіслати"),
    "bakSendConnection": MessageLookupByLibrary.simpleMessage("З\'єднання"),
    "bakSendFailed": m40,
    "bakSendFolder": MessageLookupByLibrary.simpleMessage(
      "Тека (задана на хості)",
    ),
    "bakSendLink": MessageLookupByLibrary.simpleMessage(
      "Лінк файлового сховища",
    ),
    "bakSendPath": MessageLookupByLibrary.simpleMessage(
      "Ім\'я файлу або підшлях",
    ),
    "bakSendPathNote": MessageLookupByLibrary.simpleMessage(
      "Порожньо: власне ім\'я файлу копії. Підтека має існувати; наявне ім\'я відхиляється, не замінюється.",
    ),
    "bakSending": m41,
    "bakSensitive": MessageLookupByLibrary.simpleMessage(
      "Резервна копія така ж чутлива, як каталог даних брокера: тримайте її там, куди мають доступ лише адміністратори.",
    ),
    "bakShow": MessageLookupByLibrary.simpleMessage(
      "Показати в резервних копіях",
    ),
    "bakSub": MessageLookupByLibrary.simpleMessage(
      "Виберіть, що потрапить у файл. Один файл .wyrm-backup (zip із маніфестом); брокер працює, поки його створюють.",
    ),
    "bakSubLink": m42,
    "bakTagAlways": MessageLookupByLibrary.simpleMessage("завжди"),
    "bakTagPassphrase": MessageLookupByLibrary.simpleMessage("парольна фраза"),
    "bakTagSite": MessageLookupByLibrary.simpleMessage(
      "запечатано для цього сайту",
    ),
    "bakTitle": m43,
    "bakTitleLink": m44,
    "bakWhatGoesIn": MessageLookupByLibrary.simpleMessage(
      "Що потрапляє у файл",
    ),
    "bakWhere": MessageLookupByLibrary.simpleMessage("Куди"),
    "bakWhereBroker": MessageLookupByLibrary.simpleMessage(
      "Залишити на брокері",
    ),
    "bakWhereBrokerNote": m45,
    "bakWhereComputer": MessageLookupByLibrary.simpleMessage("Цей комп\'ютер"),
    "bakWhereComputerNote": m46,
    "bakWhereStore": MessageLookupByLibrary.simpleMessage(
      "Лінк файлового сховища…",
    ),
    "bakWhereStoreNote": MessageLookupByLibrary.simpleMessage(
      "Лінк файлового сховища (S3, WebDAV, диск) бере її з брокера, оминаючи цей комп\'ютер.",
    ),
    "bakWorking": MessageLookupByLibrary.simpleMessage("Створення копії…"),
    "bindHint": MessageLookupByLibrary.simpleMessage(
      "Перетягніть сюди вихід, щоб зв’язати",
    ),
    "block": MessageLookupByLibrary.simpleMessage("Блок"),
    "blockForm": MessageLookupByLibrary.simpleMessage("Форма"),
    "blockInputs": MessageLookupByLibrary.simpleMessage("Входи"),
    "blockOutputs": MessageLookupByLibrary.simpleMessage("Виходи"),
    "blocksCount": m47,
    "boundMark": MessageLookupByLibrary.simpleMessage("зв’язано"),
    "branchOrTag": MessageLookupByLibrary.simpleMessage("гілка або тег"),
    "bringOne": MessageLookupByLibrary.simpleMessage(
      "Оберіть файл або вкажіть, де пакет.",
    ),
    "brokerLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив зміну; наступні не застосовано.",
    ),
    "brokerSays": MessageLookupByLibrary.simpleMessage("Брокер каже"),
    "brokerWaiting": MessageLookupByLibrary.simpleMessage("Брокер чекає"),
    "brokersDevices": m48,
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m49,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "bupBackOn": m50,
    "bupBackOnNote": m51,
    "bupCard": MessageLookupByLibrary.simpleMessage("Версія брокера"),
    "bupCardAvailable": m52,
    "bupCardCurrent": m53,
    "bupCardRolledBack": m54,
    "bupCardTrial": m55,
    "bupCheckConfig": MessageLookupByLibrary.simpleMessage(
      "Новий бінарник приймає цю конфігурацію",
    ),
    "bupCheckConfigNote": MessageLookupByLibrary.simpleMessage(
      "Новий wyrmd виконує перевірку конфігурації цього брокера.",
    ),
    "bupCheckRoom": MessageLookupByLibrary.simpleMessage("Місце для нього"),
    "bupCheckRoomNote": MessageLookupByLibrary.simpleMessage(
      "Бінарник і резервна копія перед оновленням уміщаються на диску.",
    ),
    "bupCheckSchema": MessageLookupByLibrary.simpleMessage(
      "Формат сховища може змінитися",
    ),
    "bupCheckSchemaNote": m56,
    "bupCheckSigned": MessageLookupByLibrary.simpleMessage("Випуск підписано"),
    "bupCheckSignedNote": MessageLookupByLibrary.simpleMessage(
      "Підпис Ed25519 ключем випуску та SHA-256 архіву.",
    ),
    "bupCheckStandby": MessageLookupByLibrary.simpleMessage(
      "Спершу оновлюють резервний брокер",
    ),
    "bupCheckStandbyNote": MessageLookupByLibrary.simpleMessage(
      "Коли за цим брокером стежить резервний і випуск змінює протокол реплікації, брокер відмовляє, доки резервний не працює на новій версії.",
    ),
    "bupChecked": MessageLookupByLibrary.simpleMessage(
      "Перевіряється до будь-яких змін",
    ),
    "bupClosing": MessageLookupByLibrary.simpleMessage(
      "Закриття Studio його не зупиняє.",
    ),
    "bupDo": MessageLookupByLibrary.simpleMessage("Створити копію й оновити"),
    "bupDoneBack": MessageLookupByLibrary.simpleMessage(
      "Роутер, шлюз, лінки повернулися",
    ),
    "bupDoneConfirmed": MessageLookupByLibrary.simpleMessage("Підтверджено"),
    "bupDonePreBackup": MessageLookupByLibrary.simpleMessage(
      "Копія перед оновленням",
    ),
    "bupDoneRestart": m57,
    "bupDoneStaged": m58,
    "bupExternal": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не замінює себе сам (updates.mode: \"external\": контейнер або пакет дистрибутива). Образ змінюють там, де визначено контейнер, а том даних переносить стан.",
    ),
    "bupExternalBackup": MessageLookupByLibrary.simpleMessage(
      "Studio все одно створить для вас резервну копію перед цим.",
    ),
    "bupFactAudit": MessageLookupByLibrary.simpleMessage("Аудит"),
    "bupFactDown": MessageLookupByLibrary.simpleMessage("Без брокера"),
    "bupFactLinks": MessageLookupByLibrary.simpleMessage("Лінки повернулися"),
    "bupFactNow": MessageLookupByLibrary.simpleMessage("Зараз"),
    "bupFactReason": MessageLookupByLibrary.simpleMessage("Причина"),
    "bupFactRollBack": MessageLookupByLibrary.simpleMessage("Відкат"),
    "bupFactTried": MessageLookupByLibrary.simpleMessage("Спроба"),
    "bupFactVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "bupHide": MessageLookupByLibrary.simpleMessage("Сховати"),
    "bupHow": MessageLookupByLibrary.simpleMessage("Як це відбувається"),
    "bupLinksBack": m59,
    "bupLost": m60,
    "bupMakeBackup": MessageLookupByLibrary.simpleMessage("Створити копію"),
    "bupMeanwhile": MessageLookupByLibrary.simpleMessage(
      "Лінки на інших машинах переходять до наступної точки або чекають; пристрої зберігають останні виходи. Значення, записані лінками під час перезапуску, не втрачаються, якщо лінк їх буферизує.",
    ),
    "bupNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Потрібен config на sys · з аудитом",
    ),
    "bupOnTrial": MessageLookupByLibrary.simpleMessage(
      "Шлюз повернувся; нова версія на випробуванні.",
    ),
    "bupOpenLog": m61,
    "bupPillContainer": MessageLookupByLibrary.simpleMessage("контейнер"),
    "bupPillRestarting": MessageLookupByLibrary.simpleMessage("перезапуск"),
    "bupReconnecting": MessageLookupByLibrary.simpleMessage("Під\'єднання…"),
    "bupRestarting": m62,
    "bupRollBackNote": MessageLookupByLibrary.simpleMessage(
      "Брокер перезапуститься на попередній версії й відновить копію площини керування, зроблену перед оновленням. Зміни після оновлення втрачаються.",
    ),
    "bupRollBackTitle": m63,
    "bupRollBackUntil": m64,
    "bupRolledBack": MessageLookupByLibrary.simpleMessage(
      "Оновлення відкочено",
    ),
    "bupRuns": m65,
    "bupRunsNote": m66,
    "bupSeconds": m67,
    "bupShow": MessageLookupByLibrary.simpleMessage("Показати…"),
    "bupStep1": MessageLookupByLibrary.simpleMessage(
      "Резервна копія площини керування перед оновленням, секрети запечатано (зберігається до підтвердження оновлення).",
    ),
    "bupStep2": m68,
    "bupStep3": m69,
    "bupStep4": m70,
    "bupStep5": m71,
    "bupSub": MessageLookupByLibrary.simpleMessage(
      "З каналу випусків цього брокера · брокер перезапускається один раз",
    ),
    "bupTitle": m72,
    "bupType": m73,
    "bupUpdate": MessageLookupByLibrary.simpleMessage("Оновити…"),
    "bupUpdated": m74,
    "bupUpdating": m75,
    "bupUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Цей екран під\'єднується самостійно.",
    ),
    "caSigned": m76,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "нічого: ні читання, ні запису",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "cancelTask": MessageLookupByLibrary.simpleMessage("Скасувати задачу"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Не вдалося з’єднатися з gateway",
    ),
    "cantReachGateway": MessageLookupByLibrary.simpleMessage(
      "Gateway не відповідає",
    ),
    "catalogAll": MessageLookupByLibrary.simpleMessage("Усі"),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований: у wyrmd, нічого не завантажується. Пакет: з індексу packages.repository, SHA-256 перевіряється; брокер показує лише пакети, які може встановити.",
    ),
    "catalogProcessForm": m77,
    "cbBadName": MessageLookupByLibrary.simpleMessage(
      "Назва має лише літери, цифри та _",
    ),
    "cbBadPort": MessageLookupByLibrary.simpleMessage(
      "Назва порту має лише літери, цифри та _",
    ),
    "cbCreate": MessageLookupByLibrary.simpleMessage("Створити"),
    "cbDefault": MessageLookupByLibrary.simpleMessage("за замовчуванням"),
    "cbDescription": MessageLookupByLibrary.simpleMessage("Опис"),
    "cbDuplicate": MessageLookupByLibrary.simpleMessage(
      "Два порти мають однакову назву",
    ),
    "cbInputs": MessageLookupByLibrary.simpleMessage("Входи"),
    "cbLimit": MessageLookupByLibrary.simpleMessage(
      "Не більше 64 блоків, 64 входів і 64 виходів у кожному",
    ),
    "cbName": MessageLookupByLibrary.simpleMessage("Назва"),
    "cbNone": MessageLookupByLibrary.simpleMessage("немає"),
    "cbNote": m78,
    "cbOutputs": MessageLookupByLibrary.simpleMessage("Виходи"),
    "cbTaken": MessageLookupByLibrary.simpleMessage(
      "Цей флоу вже має блок з такою назвою",
    ),
    "cbTitle": MessageLookupByLibrary.simpleMessage("Створити власний блок"),
    "cfgApiKey": MessageLookupByLibrary.simpleMessage("Секрет API-ключа"),
    "cfgApproval": MessageLookupByLibrary.simpleMessage("Схвалення для"),
    "cfgBudget": MessageLookupByLibrary.simpleMessage("Токенів на день"),
    "cfgModel": MessageLookupByLibrary.simpleMessage("Модель"),
    "cfgPrefixes": MessageLookupByLibrary.simpleMessage("Може змінювати"),
    "changeAnswers": MessageLookupByLibrary.simpleMessage("Змінити відповіді"),
    "changeOpAdd": MessageLookupByLibrary.simpleMessage("Додавання"),
    "changeOpEdit": MessageLookupByLibrary.simpleMessage("Зміна"),
    "changeOpRemove": MessageLookupByLibrary.simpleMessage("Видалення"),
    "changesGuess": m79,
    "checkAtRun": MessageLookupByLibrary.simpleMessage(
      "перевіряється під час виконання: вузол створює попередній крок",
    ),
    "checkFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку: принесіть інший.",
    ),
    "checkNow": MessageLookupByLibrary.simpleMessage(
      "перевірено на живому дереві",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Перевірте з’єднання та спробуйте ще раз.",
    ),
    "checkedHere": MessageLookupByLibrary.simpleMessage(
      "Перевірено тут; брокер перевірить ще раз перед встановленням.",
    ),
    "checkingGateway": MessageLookupByLibrary.simpleMessage(
      "Перевірка gateway",
    ),
    "childCount": m80,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Вибери рядок: вузол відкривається в дереві, значення — в інспекторі.",
    ),
    "choicesConfirm": MessageLookupByLibrary.simpleMessage("Написати план"),
    "choicesFromCard": m81,
    "choicesNoAnswer": MessageLookupByLibrary.simpleMessage("без відповіді"),
    "choicesNote": MessageLookupByLibrary.simpleMessage(
      "Або дайте відповідь своїми словами нижче.",
    ),
    "choicesOwnWords": m82,
    "choicesPickOne": MessageLookupByLibrary.simpleMessage(
      "Оберіть варіант або дайте відповідь своїми словами нижче.",
    ),
    "choicesTitle": MessageLookupByLibrary.simpleMessage("Асистент питає"),
    "chooseBackupFile": MessageLookupByLibrary.simpleMessage(
      "Виберіть файл .wyrm-link",
    ),
    "chooseWasm": MessageLookupByLibrary.simpleMessage(
      "Оберіть компонент .wasm",
    ),
    "chooseZip": MessageLookupByLibrary.simpleMessage("Оберіть пакет .zip"),
    "clearConns": MessageLookupByLibrary.simpleMessage(
      "Прибрати від’єднані лінки",
    ),
    "clearConnsNote": MessageLookupByLibrary.simpleMessage(
      "Видаляє зовнішні лінки, які не під’єднані; їхні id вилучаються.",
    ),
    "clearSelection": MessageLookupByLibrary.simpleMessage("Очистити"),
    "closeDrawer": MessageLookupByLibrary.simpleMessage("Закрити (Cmd+J)"),
    "closeLabel": MessageLookupByLibrary.simpleMessage("Закрити"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colDeployedBy": MessageLookupByLibrary.simpleMessage("Хто розгорнув"),
    "colDevices": MessageLookupByLibrary.simpleMessage("Пристрої"),
    "colFlow": MessageLookupByLibrary.simpleMessage("Потік"),
    "colFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "colKind": MessageLookupByLibrary.simpleMessage("Вид"),
    "colLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "colLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Лінк · пристрій"),
    "colMode": MessageLookupByLibrary.simpleMessage("Режим"),
    "colName": MessageLookupByLibrary.simpleMessage("Назва"),
    "colOp": MessageLookupByLibrary.simpleMessage("Що"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "colPoll": MessageLookupByLibrary.simpleMessage("Опитування"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Якість"),
    "colReadRows": MessageLookupByLibrary.simpleMessage("Значень на тренді"),
    "colReadsWrites": MessageLookupByLibrary.simpleMessage("Читає → пише"),
    "colRegister": MessageLookupByLibrary.simpleMessage("Регістр"),
    "colResult": MessageLookupByLibrary.simpleMessage("Результат"),
    "colRole": MessageLookupByLibrary.simpleMessage("Роль"),
    "colRoles": MessageLookupByLibrary.simpleMessage("Ролі"),
    "colRows": MessageLookupByLibrary.simpleMessage("Рядків показано"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "colSource": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colState": MessageLookupByLibrary.simpleMessage("Стан"),
    "colTime": MessageLookupByLibrary.simpleMessage("Час"),
    "colType": MessageLookupByLibrary.simpleMessage("Тип"),
    "colUnit": MessageLookupByLibrary.simpleMessage("Одиниця"),
    "colUser": MessageLookupByLibrary.simpleMessage("Користувач"),
    "colValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Версія · джерело",
    ),
    "colWatch": MessageLookupByLibrary.simpleMessage("Спостереження"),
    "colWho": MessageLookupByLibrary.simpleMessage("Хто"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Чому тут"),
    "colWrite": MessageLookupByLibrary.simpleMessage("Запис"),
    "collecting": MessageLookupByLibrary.simpleMessage("Збираю значення…"),
    "commandNote": MessageLookupByLibrary.simpleMessage(
      "Його натискає семпл на дроті. Під\'єднайте до нього подію (таймер, зміну, точку); Studio не може натиснути його у флоу, що працює.",
    ),
    "composerReplaces": MessageLookupByLibrary.simpleMessage(
      "Надсилання просить новий план: цей план буде замінено, і його вже не можна буде схвалити.",
    ),
    "configAllowed": MessageLookupByLibrary.simpleMessage(
      "config дозволено для цього верхнього",
    ),
    "configureStaged": MessageLookupByLibrary.simpleMessage(
      "Налаштування · підготовлено",
    ),
    "configureStagedNote": MessageLookupByLibrary.simpleMessage(
      "Готуються разом з іншими змінами; застосовуються в перегляді.",
    ),
    "connect": MessageLookupByLibrary.simpleMessage("Під’єднати"),
    "connectNote": m83,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Під’єднати до верхнього",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Далі"),
    "controlPlane": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "copiedValue": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "copyKey": MessageLookupByLibrary.simpleMessage("Копіювати ключ"),
    "copyKeys": MessageLookupByLibrary.simpleMessage("Копіювати ключі"),
    "copyText": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "copyValue": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "Архів пакета, який ви приносите: zip, URL, Git-репозиторій або один .wasm. Перевіряється перед встановленням.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "dataDir": m84,
    "dataflow": MessageLookupByLibrary.simpleMessage("Потік даних"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Його права тут забрано зараз, наступне з’єднання чекатиме в карантині. Його сайти лишаються під ним.",
    ),
    "deauthorizeTitle": m85,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Вирішити в Лінках"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Лінк у карантині схвалюють або відхиляють у Лінках › Карантин.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "deploy": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "deployAskMessage": m86,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage(
      "Розгорнути цей потік?",
    ),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Щоб розгорнути, повернися до флоу",
    ),
    "deployedByWho": m87,
    "deploying": MessageLookupByLibrary.simpleMessage("Розгортання…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Усі частини дизайн-системи (лише для розробки).",
    ),
    "deviceForgetText": MessageLookupByLibrary.simpleMessage(
      "Запис зникає зі шлюзу.",
    ),
    "deviceForgetTitle": m88,
    "deviceLine": m89,
    "deviceRemoveText": m90,
    "deviceRemoveTitle": m91,
    "devicesNone": MessageLookupByLibrary.simpleMessage("Пристроїв немає."),
    "disableUser": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнений користувач не може увійти; ролі лишаються.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discoverFound": m92,
    "discoverLooking": m93,
    "discoverNoneTitle": m94,
    "discoverNothing": MessageLookupByLibrary.simpleMessage(
      "Нічого не знайдено",
    ),
    "discoverPanel": MessageLookupByLibrary.simpleMessage(
      "Gateway у цій мережі",
    ),
    "discoverProbed": m95,
    "discoverProbing": m96,
    "doneLeftOutNote": m97,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "Задачу виконано. План і журнал лишаються в її записі.",
    ),
    "doneOnTheDevice": m98,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("нижче"),
    "downstreamBroker": MessageLookupByLibrary.simpleMessage("Брокер нижче"),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "draftCopied": MessageLookupByLibrary.simpleMessage("Скопійовано."),
    "draftNote": MessageLookupByLibrary.simpleMessage(
      "План і далі чекає на ваше схвалення: нікому нічого не надіслано. Скопіюйте текст і надішліть його самі.",
    ),
    "draftSaved": MessageLookupByLibrary.simpleMessage("Чернетку збережено"),
    "draftTileNote": MessageLookupByLibrary.simpleMessage(
      "чернетка для копіювання · нічого не надсилає",
    ),
    "draftTitle": MessageLookupByLibrary.simpleMessage(
      "Повідомлення для копіювання",
    ),
    "draftValid": MessageLookupByLibrary.simpleMessage(
      "Чернетка · правильна, не розгорнута",
    ),
    "drawerHint": MessageLookupByLibrary.simpleMessage(
      "Спитайте про те, що бачите… (Cmd+Enter)",
    ),
    "drawerSuggests": MessageLookupByLibrary.simpleMessage("Асистент пропонує"),
    "drawerTitle": MessageLookupByLibrary.simpleMessage("Асистент"),
    "dropRead": MessageLookupByLibrary.simpleMessage("Читати"),
    "dropWrite": MessageLookupByLibrary.simpleMessage("Писати"),
    "editDataflow": MessageLookupByLibrary.simpleMessage("Редагувати потік"),
    "editDataflowNote": MessageLookupByLibrary.simpleMessage(
      "Відкрити в редакторі; нічого не змінюється до розгортання.",
    ),
    "editGroup": MessageLookupByLibrary.simpleMessage("Змінити групу"),
    "editGroupNote": MessageLookupByLibrary.simpleMessage(
      "Як і як часто записуються точки.",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» застосовується з іншими змінами; лінк перезапуститься з новою ревізією.",
    ),
    "editParamsOf": m99,
    "enableUser": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "errAdviceBroker": m100,
    "errAdviceBrokerSaid": MessageLookupByLibrary.simpleMessage(
      "Виклик дійшов до брокера, і він відмовив. Перевірте те, що він назвав вище.",
    ),
    "errAdviceBusy": MessageLookupByLibrary.simpleMessage(
      "Зачекайте трохи та спробуйте ще раз.",
    ),
    "errAdviceBusyAuto": MessageLookupByLibrary.simpleMessage(
      "Studio спробує ще раз сама, коли брокер буде готовий.",
    ),
    "errAdviceGone": MessageLookupByLibrary.simpleMessage(
      "Хтось вилучив або перейменував це після завантаження екрана. Оновіть, щоб побачити поточний стан.",
    ),
    "errAdviceInput": MessageLookupByLibrary.simpleMessage(
      "Поверніться до форми, виправте значення та надішліть знову.",
    ),
    "errAdviceInputField": m101,
    "errAdviceReach": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо помилка повторюється, перевірте стан лінка в Links.",
    ),
    "errAdviceReachLogin": MessageLookupByLibrary.simpleMessage(
      "Увійдіть знову: Studio не має сесії з gateway.",
    ),
    "errAdviceReport": MessageLookupByLibrary.simpleMessage(
      "Скопіюйте звіт і надішліть нам: він не містить значень і паролів.",
    ),
    "errAdviceRights": MessageLookupByLibrary.simpleMessage(
      "Попросіть адміністратора надати право або зробити це.",
    ),
    "errAdviceRightsRole": m102,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо повторюється, перезапустіть Studio.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Цей брокер або лінк не має такого виклику; можливо, він старіший, ніж очікує Studio.",
    ),
    "errAgentParamsUnread": MessageLookupByLibrary.simpleMessage(
      "Параметри лінка агента не вдалося прочитати, тому нічого не підготовлено.",
    ),
    "errAssistantNoTask": MessageLookupByLibrary.simpleMessage(
      "Асистент не почав жодного завдання. Перевірте, чи задано його ключ API.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Назад до форми"),
    "errBackupDigestMismatch": m103,
    "errBackupNoDigest": MessageLookupByLibrary.simpleMessage(
      "Брокер не показує SHA-256 цієї резервної копії, тому отримане не можна перевірити. Нічого не збережено.",
    ),
    "errCallOn": m104,
    "errChipStudio": m105,
    "errCopied": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage(
      "Копіювати подробиці",
    ),
    "errCopyLine": m106,
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Копіювати звіт"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Подробиці"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "Подробиці в буфері обміну.",
    ),
    "errDoDeploy": m107,
    "errDoInstall": m108,
    "errDoList": m109,
    "errDoLogIn": m110,
    "errDoOpen": m111,
    "errDoRead": m112,
    "errDoRemove": m113,
    "errDoRun": m114,
    "errDoSave": m115,
    "errDoStart": m116,
    "errDoStep": m117,
    "errDoStop": m118,
    "errDoWrite": m119,
    "errDoingDeploy": m120,
    "errDoingInstall": m121,
    "errDoingList": m122,
    "errDoingLogIn": m123,
    "errDoingOpen": m124,
    "errDoingRead": m125,
    "errDoingRemove": m126,
    "errDoingRun": m127,
    "errDoingSave": m128,
    "errDoingStart": m129,
    "errDoingStop": m130,
    "errDoingWrite": m131,
    "errEmptyPart": MessageLookupByLibrary.simpleMessage(
      "Брокер надіслав порожню частину до кінця файлу.",
    ),
    "errFaultMessage": MessageLookupByLibrary.simpleMessage(
      "Тут стався збій у Studio. Це помилка Studio, а не брокера; більше нічого не надіслано.",
    ),
    "errFileEndedEarly": m132,
    "errFlowDefInvalid": m133,
    "errLibraryBlockInvalid": m134,
    "errNoAssistant": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті немає лінка асистента.",
    ),
    "errNoDeviceKey": m135,
    "errNoEditAction": MessageLookupByLibrary.simpleMessage(
      "Цей вузол не має дії edit.",
    ),
    "errNotConnected": MessageLookupByLibrary.simpleMessage(
      "Studio не підключена до шлюзу.",
    ),
    "errNotSettable": MessageLookupByLibrary.simpleMessage(
      "Його meta не називає рівня, на якому значення можна записати, тому нічого не підготовлено.",
    ),
    "errNounDeploy": MessageLookupByLibrary.simpleMessage("розгортання"),
    "errNounInstall": MessageLookupByLibrary.simpleMessage("встановлення"),
    "errNounList": MessageLookupByLibrary.simpleMessage("список"),
    "errNounLogIn": MessageLookupByLibrary.simpleMessage("вхід"),
    "errNounOpen": MessageLookupByLibrary.simpleMessage("відкриття"),
    "errNounRead": MessageLookupByLibrary.simpleMessage("читання"),
    "errNounRemove": MessageLookupByLibrary.simpleMessage("вилучення"),
    "errNounRun": m136,
    "errNounSave": MessageLookupByLibrary.simpleMessage("збереження"),
    "errNounStart": MessageLookupByLibrary.simpleMessage("запуск"),
    "errNounStop": MessageLookupByLibrary.simpleMessage("зупинка"),
    "errNounWrite": MessageLookupByLibrary.simpleMessage("запис"),
    "errOpenLog": MessageLookupByLibrary.simpleMessage("Відкрити журнал"),
    "errPackageHasNoLink": m137,
    "errPortOutOfRange": MessageLookupByLibrary.simpleMessage(
      "Порт — від 1 до 65535.",
    ),
    "errProfileNotJson": m138,
    "errProfileNotObject": MessageLookupByLibrary.simpleMessage(
      "Профіль — це об’єкт JSON.",
    ),
    "errProfileTooBig": MessageLookupByLibrary.simpleMessage(
      "У профілі забагато записів, щоб додати extends.",
    ),
    "errProfileUnknownKey": m139,
    "errProfileUnknownType": m140,
    "errRefresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "errReportCopied": MessageLookupByLibrary.simpleMessage(
      "Звіт у буфері обміну.",
    ),
    "errReportNote": MessageLookupByLibrary.simpleMessage(
      "трасування стека є лише у скопійованому звіті",
    ),
    "errRowAs": MessageLookupByLibrary.simpleMessage("Від імені"),
    "errRowCall": MessageLookupByLibrary.simpleMessage("Виклик"),
    "errRowError": MessageLookupByLibrary.simpleMessage("Помилка"),
    "errRowGateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "errRowIn": MessageLookupByLibrary.simpleMessage("Де"),
    "errRowMessage": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "errRowReport": MessageLookupByLibrary.simpleMessage("Звіт"),
    "errRowScreen": MessageLookupByLibrary.simpleMessage("Екран"),
    "errRowSite": MessageLookupByLibrary.simpleMessage("Сайт"),
    "errRowStatus": MessageLookupByLibrary.simpleMessage("Статус"),
    "errRowStudio": MessageLookupByLibrary.simpleMessage("Studio"),
    "errRowTime": MessageLookupByLibrary.simpleMessage("Час"),
    "errRunDenied": MessageLookupByLibrary.simpleMessage(
      "Тобі не можна запустити його: це потребує write на флоу і прав на те, на що діють блок і блоки після нього.",
    ),
    "errRunNoTrigger": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має дії trigger (потрібен ADR 0040).",
    ),
    "errRunNotByHand": MessageLookupByLibrary.simpleMessage(
      "Цей блок не можна запустити вручну.",
    ),
    "errRunNotRunning": MessageLookupByLibrary.simpleMessage("Флоу не працює."),
    "errSaidBroker": MessageLookupByLibrary.simpleMessage("Брокер відповів"),
    "errSaidNoAnswer": MessageLookupByLibrary.simpleMessage("Studio чекала"),
    "errSaidStudio": MessageLookupByLibrary.simpleMessage("Що сталося"),
    "errSeeAccess": MessageLookupByLibrary.simpleMessage("Мої права"),
    "errSignCancelled": MessageLookupByLibrary.simpleMessage(
      "Запит скасовано.",
    ),
    "errSignKeyGone": MessageLookupByLibrary.simpleMessage(
      "Ключ більше не відкривається.",
    ),
    "errSignLockedOut": MessageLookupByLibrary.simpleMessage(
      "Система заблокувала ключ після забагатьох спроб.",
    ),
    "errSignUnavailable": MessageLookupByLibrary.simpleMessage(
      "Біометрія на цьому комп’ютері недоступна.",
    ),
    "errSilentReach": m141,
    "errSilentStatus": m142,
    "errStatusLine": m143,
    "errTaskRecordInvalid": m144,
    "errThingAssistant": MessageLookupByLibrary.simpleMessage("асистента"),
    "errThingBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "errThingDevice": m145,
    "errThingProfile": MessageLookupByLibrary.simpleMessage("профіль"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("це"),
    "errTimeLocal": m146,
    "errTitleBroker": m147,
    "errTitleBrokerNoSite": m148,
    "errTitleBusy": m149,
    "errTitleGone": m150,
    "errTitleHistory": m151,
    "errTitleInput": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив ці параметри",
    ),
    "errTitleInputValue": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив це значення",
    ),
    "errTitleNotConnected": MessageLookupByLibrary.simpleMessage(
      "Studio не з’єднана з gateway",
    ),
    "errTitlePlain": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося це завершити",
    ),
    "errTitleReach": m152,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "Брокер не відповідає",
    ),
    "errTitleRead": m153,
    "errTitleRights": m154,
    "errTitleStream": m155,
    "errTitleStudio": m156,
    "errTitleUnsupported": m157,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще раз"),
    "errTryAgainIn": m158,
    "errUserRole": m159,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("Що можна зробити"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "Запис, що не дочекався відповіді, міг бути застосований. Перевірте значення, перш ніж надсилати знову.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("ще не було"),
    "everySeconds": m160,
    "factAbout": MessageLookupByLibrary.simpleMessage("Про"),
    "factAgent": MessageLookupByLibrary.simpleMessage("Агент"),
    "factAllowConfig": MessageLookupByLibrary.simpleMessage("Config від нього"),
    "factAskedBy": MessageLookupByLibrary.simpleMessage("Запитав"),
    "factBelow": MessageLookupByLibrary.simpleMessage("Нижче"),
    "factBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "factBranch": MessageLookupByLibrary.simpleMessage("Гілка"),
    "factBuild": MessageLookupByLibrary.simpleMessage("Збірка"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Може"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "factDeployedBy": MessageLookupByLibrary.simpleMessage("Розгорнув"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "factEvents": MessageLookupByLibrary.simpleMessage("Події"),
    "factFlush": MessageLookupByLibrary.simpleMessage("Скидання"),
    "factFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "factGrants": MessageLookupByLibrary.simpleMessage("Дозволи"),
    "factHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "factInterval": MessageLookupByLibrary.simpleMessage("Інтервал"),
    "factKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "factKind": MessageLookupByLibrary.simpleMessage("Тип"),
    "factLive": MessageLookupByLibrary.simpleMessage("Живі значення"),
    "factLogLevel": MessageLookupByLibrary.simpleMessage("Рівень журналу"),
    "factMayWrite": MessageLookupByLibrary.simpleMessage("Може писати"),
    "factOldest": MessageLookupByLibrary.simpleMessage("Найстаріший день"),
    "factProblem": MessageLookupByLibrary.simpleMessage("Проблема"),
    "factReads": MessageLookupByLibrary.simpleMessage("Читає"),
    "factRecord": MessageLookupByLibrary.simpleMessage("Запис"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Ретранслює"),
    "factRestorePoints": MessageLookupByLibrary.simpleMessage(
      "Точки відновлення",
    ),
    "factRowsWritten": MessageLookupByLibrary.simpleMessage("Записано рядків"),
    "factRunning": MessageLookupByLibrary.simpleMessage("Працює"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Побачено"),
    "factSentTo": MessageLookupByLibrary.simpleMessage("Куди надсилається"),
    "factSince": MessageLookupByLibrary.simpleMessage("Від"),
    "factStarted": MessageLookupByLibrary.simpleMessage("Запущено"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Стан"),
    "factSubject": MessageLookupByLibrary.simpleMessage("Суб’єкт"),
    "factTask": MessageLookupByLibrary.simpleMessage("Задача"),
    "factTaskState": MessageLookupByLibrary.simpleMessage("Стан"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Через"),
    "factToday": MessageLookupByLibrary.simpleMessage("Сьогодні"),
    "factTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Верхні"),
    "factValues": MessageLookupByLibrary.simpleMessage("Значення"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "factVersionOf": m161,
    "factWrites": MessageLookupByLibrary.simpleMessage("Пише"),
    "failed": MessageLookupByLibrary.simpleMessage("не пройшов"),
    "failedNote": MessageLookupByLibrary.simpleMessage(
      "Задача зупинилась. Те, що вже зроблено, лишається.",
    ),
    "fatalBody": MessageLookupByLibrary.simpleMessage(
      "Налаштування, збережені на цьому комп’ютері, не читаються, тому Studio не знає, які gateway ви використовуєте. Ваші брокери не зачеплено: ніщо на них не залежить від Studio.",
    ),
    "fatalFile": MessageLookupByLibrary.simpleMessage("Файл"),
    "fatalFresh": MessageLookupByLibrary.simpleMessage(
      "Почати з чистими налаштуваннями",
    ),
    "fatalMoveFailed": m162,
    "fatalNote": m163,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Вийти зі Studio"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося запустити",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "Решта Studio працює; значення та дії в інших місцях не зачеплено.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Намалювати ще раз"),
    "faultProblem": m164,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("цю частину"),
    "faultTitle": m165,
    "faultTitleThis": MessageLookupByLibrary.simpleMessage(
      "Цю частину не вдалося намалювати",
    ),
    "faultUncaught": MessageLookupByLibrary.simpleMessage(
      "У Studio стався збій у фоні",
    ),
    "fieldAddress": MessageLookupByLibrary.simpleMessage("Адреса"),
    "fieldArea": MessageLookupByLibrary.simpleMessage("Область"),
    "fieldBit": MessageLookupByLibrary.simpleMessage("Біт"),
    "fieldDataType": MessageLookupByLibrary.simpleMessage("Тип даних"),
    "fieldNumbered": m166,
    "fieldOffset": MessageLookupByLibrary.simpleMessage("Зсув"),
    "fieldPrecision": MessageLookupByLibrary.simpleMessage("Точність"),
    "fieldRegisters": MessageLookupByLibrary.simpleMessage("Регістри"),
    "fieldScale": MessageLookupByLibrary.simpleMessage("Масштаб"),
    "fieldUnit": MessageLookupByLibrary.simpleMessage("Одиниця"),
    "fieldWordAbsoluteChange": MessageLookupByLibrary.simpleMessage(
      "Абсолютна зміна",
    ),
    "fieldWordActive": MessageLookupByLibrary.simpleMessage("Активна"),
    "fieldWordAlive": MessageLookupByLibrary.simpleMessage("На зв’язку"),
    "fieldWordAllowBadQuality": MessageLookupByLibrary.simpleMessage(
      "Дозволити погану якість",
    ),
    "fieldWordAutoRun": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "fieldWordAverage": MessageLookupByLibrary.simpleMessage("Середнє"),
    "fieldWordCaseOf": MessageLookupByLibrary.simpleMessage("Випадок"),
    "fieldWordCount": MessageLookupByLibrary.simpleMessage("Кількість"),
    "fieldWordDelayMs": MessageLookupByLibrary.simpleMessage("Затримка (мс)"),
    "fieldWordDelimiter": MessageLookupByLibrary.simpleMessage("Роздільник"),
    "fieldWordEvery": MessageLookupByLibrary.simpleMessage("Кожні"),
    "fieldWordExpression": MessageLookupByLibrary.simpleMessage("Вираз"),
    "fieldWordFactor": MessageLookupByLibrary.simpleMessage("Множник"),
    "fieldWordFunction": MessageLookupByLibrary.simpleMessage("Функція"),
    "fieldWordInput": MessageLookupByLibrary.simpleMessage("Вхід"),
    "fieldWordInputOutOfRange": MessageLookupByLibrary.simpleMessage(
      "Вхід поза діапазоном",
    ),
    "fieldWordIntervalS": MessageLookupByLibrary.simpleMessage("Інтервал (с)"),
    "fieldWordMaxSamples": MessageLookupByLibrary.simpleMessage(
      "Макс. зразків",
    ),
    "fieldWordMemoryMb": MessageLookupByLibrary.simpleMessage("Пам’ять (МБ)"),
    "fieldWordMessage": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "fieldWordMeta": MessageLookupByLibrary.simpleMessage("Метадані"),
    "fieldWordNode": MessageLookupByLibrary.simpleMessage("Вузол"),
    "fieldWordOffset": MessageLookupByLibrary.simpleMessage("Зсув"),
    "fieldWordOnBadQuality": MessageLookupByLibrary.simpleMessage(
      "За поганої якості",
    ),
    "fieldWordOperation": MessageLookupByLibrary.simpleMessage("Операція"),
    "fieldWordOrder": MessageLookupByLibrary.simpleMessage("Порядок слів"),
    "fieldWordOutput": MessageLookupByLibrary.simpleMessage("Вихід"),
    "fieldWordPercentChange": MessageLookupByLibrary.simpleMessage(
      "Зміна у відсотках",
    ),
    "fieldWordPeriodMs": MessageLookupByLibrary.simpleMessage("Період (мс)"),
    "fieldWordPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "fieldWordQuietTimeMs": MessageLookupByLibrary.simpleMessage(
      "Час тиші (мс)",
    ),
    "fieldWordResetMode": MessageLookupByLibrary.simpleMessage(
      "Режим скидання",
    ),
    "fieldWordResult": MessageLookupByLibrary.simpleMessage("Результат"),
    "fieldWordRunOn": MessageLookupByLibrary.simpleMessage("Запускати за"),
    "fieldWordRunOnStart": MessageLookupByLibrary.simpleMessage(
      "Запуск на старті",
    ),
    "fieldWordRunWhen": MessageLookupByLibrary.simpleMessage("Запускати коли"),
    "fieldWordScope": MessageLookupByLibrary.simpleMessage("Межі"),
    "fieldWordThen": MessageLookupByLibrary.simpleMessage("Тоді"),
    "fieldWordTrigger": MessageLookupByLibrary.simpleMessage("Тригер"),
    "fieldWordValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "fieldWordValueName": MessageLookupByLibrary.simpleMessage(
      "Назва значення",
    ),
    "fieldWordWriteOn": MessageLookupByLibrary.simpleMessage("Писати за"),
    "fieldWritable": MessageLookupByLibrary.simpleMessage("Запис дозволено"),
    "fieldWritableByMaster": MessageLookupByLibrary.simpleMessage(
      "Запис від майстра",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Фільтр"),
    "filterPoints": MessageLookupByLibrary.simpleMessage("Фільтр точок"),
    "findBlock": MessageLookupByLibrary.simpleMessage("Знайти блок"),
    "findInTree": MessageLookupByLibrary.simpleMessage("Знайти точку або дію"),
    "findOnNetwork": MessageLookupByLibrary.simpleMessage(
      "Знайти в цій мережі",
    ),
    "firesAtDeploy": MessageLookupByLibrary.simpleMessage(
      "спрацює при розгортанні",
    ),
    "firesAtDeployNote": MessageLookupByLibrary.simpleMessage(
      "Параметр надсилає значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firesAtStartNote": MessageLookupByLibrary.simpleMessage(
      "Це поле надсилає своє значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firstSeen": m167,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "Чернетка не проходить перевірку.",
    ),
    "fixReplaces": MessageLookupByLibrary.simpleMessage("замінює цей план"),
    "fixReplacesModeUnknown": MessageLookupByLibrary.simpleMessage(
      "замінює цей план; невідомо, хто схвалює, тому кроки запису нового плану можуть виконатися без людини",
    ),
    "fixReplacesNoPerson": m168,
    "flowBack": MessageLookupByLibrary.simpleMessage("Назад"),
    "flowDeployed": m169,
    "flowError": m170,
    "flowName": MessageLookupByLibrary.simpleMessage("Ідентифікатор потоку"),
    "flowProblemUnknown": MessageLookupByLibrary.simpleMessage("помилка"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Кожне поле має значення, вхід і вихід. Введіть значення або перетягніть на нього будь-який вихід, щоб зв’язати.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле показує значення, яке надходить; його зв’язок і джерело світяться, коли на нього навести. Значок зв’язку веде до джерела або розв’язує.",
    ),
    "flowStopped": m171,
    "flowVersion": m172,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "Розгортання потребує config на dataflows; gateway додає ваші докази для кожної цілі. Глядачі можуть лише дивитися.",
    ),
    "flowsOn": m173,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Кожен потік працює в брокері. Ви редагуєте чернетку; нічого не змінюється до розгортання.",
    ),
    "fmBlocks": m174,
    "fmBound": MessageLookupByLibrary.simpleMessage("зв’язане"),
    "fmCanvas": MessageLookupByLibrary.simpleMessage("Полотно"),
    "fmCreateCustom": MessageLookupByLibrary.simpleMessage(
      "Створити власний блок…",
    ),
    "fmEditCustom": MessageLookupByLibrary.simpleMessage(
      "Редагувати власний блок",
    ),
    "fmFields": MessageLookupByLibrary.simpleMessage("Поля"),
    "fmFieldsTitle": MessageLookupByLibrary.simpleMessage("Поля на блоці"),
    "fmNeedsBroker": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має власних блоків (його рушій флоу старший за ADR 0040)",
    ),
    "fmNeedsEngine": MessageLookupByLibrary.simpleMessage(
      "Потрібні власні блоки в рушії",
    ),
    "fmNotCustom": MessageLookupByLibrary.simpleMessage("Це не власний блок"),
    "fmNothingSelected": MessageLookupByLibrary.simpleMessage(
      "Спершу виділіть блок",
    ),
    "fmNothingToRedo": MessageLookupByLibrary.simpleMessage(
      "Нема чого повторювати",
    ),
    "fmNothingToUndo": MessageLookupByLibrary.simpleMessage(
      "Нема чого скасовувати",
    ),
    "fmTidy": MessageLookupByLibrary.simpleMessage("Упорядкувати"),
    "fmUnpin": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "fmUnpinField": m175,
    "followNeeds": MessageLookupByLibrary.simpleMessage(
      "продовжити це завдання може лише той, хто його поставив, або користувач з config на лінку агента",
    ),
    "followUpAsk": m176,
    "followUpLeftOut": MessageLookupByLibrary.simpleMessage(
      "Попросити пропущені кроки",
    ),
    "followUpTileNote": MessageLookupByLibrary.simpleMessage(
      "нове прохання, що продовжує це завдання",
    ),
    "formLinear": MessageLookupByLibrary.simpleMessage("k × in + b"),
    "formRange": MessageLookupByLibrary.simpleMessage("Діапазон"),
    "foundBad": MessageLookupByLibrary.simpleMessage("зараз погано"),
    "foundGood": MessageLookupByLibrary.simpleMessage("зараз добре"),
    "foundNoValue": MessageLookupByLibrary.simpleMessage(
      "значення не прочитано",
    ),
    "foundNote": MessageLookupByLibrary.simpleMessage(
      "Слова належать асистентові. Кожна позначка показує живе значення вузла зараз, прочитане з вашими правами.",
    ),
    "foundRefusedExpired": m177,
    "foundRefusedInvalid": m178,
    "foundRefusedLimit": m179,
    "foundRefusedOutside": m180,
    "foundRefusedUnknown": m181,
    "foundTitle": MessageLookupByLibrary.simpleMessage(
      "Що я знайшов · лише читання",
    ),
    "foundUncertain": MessageLookupByLibrary.simpleMessage("зараз непевно"),
    "fromAddress": m182,
    "fromBackup": MessageLookupByLibrary.simpleMessage("З резервної копії"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "Резервна копія лінка (.wyrm-link), створена дією «Резервна копія…» на лінку: налаштування, приватні дані й пакет. Повертається під своїм або новим ідентифікатором.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m183,
    "gatewayNoAnswer": m184,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Користувач gateway"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m185,
    "goToSource": MessageLookupByLibrary.simpleMessage("До джерела"),
    "goUp": MessageLookupByLibrary.simpleMessage("Вгору"),
    "grantFor": m186,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Ключ або шаблон"),
    "groupBackup": MessageLookupByLibrary.simpleMessage("Резервна копія"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Змінити"),
    "groupDevices": MessageLookupByLibrary.simpleMessage("Пристрої"),
    "groupOnTheDevice": MessageLookupByLibrary.simpleMessage(
      "Робиться на пристрої, не тут",
    ),
    "groupRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "groupRun": MessageLookupByLibrary.simpleMessage("Робота"),
    "groupVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "groupWork": MessageLookupByLibrary.simpleMessage("Робота з ним"),
    "groupYouControl": MessageLookupByLibrary.simpleMessage(
      "Що ви контролюєте тут",
    ),
    "grpArguments": MessageLookupByLibrary.simpleMessage("Аргументи"),
    "grpBehaviour": MessageLookupByLibrary.simpleMessage("Поведінка"),
    "grpEvents": MessageLookupByLibrary.simpleMessage("Події"),
    "grpState": MessageLookupByLibrary.simpleMessage("Стан"),
    "grpTarget": MessageLookupByLibrary.simpleMessage("Ціль"),
    "heroHeadline1": MessageLookupByLibrary.simpleMessage(
      "Кожен пристрій, лінк і сайт",
    ),
    "heroHeadline2": MessageLookupByLibrary.simpleMessage(
      "в одному живому дереві.",
    ),
    "heroLead": MessageLookupByLibrary.simpleMessage(
      "Переглядайте, що тримають ваші брокери, додавайте лінки, впускайте пристрої, з’єднуйте сайти та будуйте потоки. Нічого не зміниться, доки ви не застосуєте зміни.",
    ),
    "hideArgs": MessageLookupByLibrary.simpleMessage("Приховати аргументи"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Сховати пароль"),
    "hideSteps": MessageLookupByLibrary.simpleMessage("Сховати кроки"),
    "hintAwaiting": MessageLookupByLibrary.simpleMessage(
      "Попросіть змінити план, напр. «пропусти крок 4»…",
    ),
    "hintDone": MessageLookupByLibrary.simpleMessage("Що далі?"),
    "hintFailed": m187,
    "hintPlanning": MessageLookupByLibrary.simpleMessage(
      "Дайте відповідь або спитайте інше…",
    ),
    "hintRunning": MessageLookupByLibrary.simpleMessage(
      "Можна писати, поки він виконується…",
    ),
    "historianKeep": m188,
    "historianSeries": m189,
    "historianSize": m190,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Лінки синхронізації читають журнал змін історика, тож нічого не губиться, поки база недоступна.",
    ),
    "historyOf": m191,
    "historyRange1h": MessageLookupByLibrary.simpleMessage("1 год"),
    "historyRange24h": MessageLookupByLibrary.simpleMessage("24 год"),
    "historyRange30d": MessageLookupByLibrary.simpleMessage("30 д"),
    "historyRange7d": MessageLookupByLibrary.simpleMessage("7 д"),
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "історія недоступна",
    ),
    "historyUnavailableTip": m192,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "hostsWithStandby": m193,
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Імпорт CSV або дерева DSA",
    ),
    "inputsCount": m194,
    "insAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "insBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "insConnection": MessageLookupByLibrary.simpleMessage("Зʼєднання"),
    "insDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "insFolder": MessageLookupByLibrary.simpleMessage("Тека"),
    "insLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "insNode": MessageLookupByLibrary.simpleMessage("Вузол"),
    "insPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "insStorage": MessageLookupByLibrary.simpleMessage("Сховище"),
    "install": MessageLookupByLibrary.simpleMessage("Встановити"),
    "installNoWords": MessageLookupByLibrary.simpleMessage(
      "Брокер не назвав причини.",
    ),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Встановлення потребує config на sys (роль admin). Нічого не встановлюється, доки ви не натиснете «Встановити».",
    ),
    "installedOn": m195,
    "instancesInFlow": m196,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Видати"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Ключ скопійовано"),
    "keysCopied": m197,
    "kindAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "kindBlockPorts": MessageLookupByLibrary.simpleMessage("Власний блок"),
    "kindBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "kindConnection": MessageLookupByLibrary.simpleMessage("зʼєднання"),
    "kindDataflow": MessageLookupByLibrary.simpleMessage("потік даних"),
    "kindDevice": MessageLookupByLibrary.simpleMessage("пристрій"),
    "kindFlow": MessageLookupByLibrary.simpleMessage("Потік"),
    "kindFolder": MessageLookupByLibrary.simpleMessage("тека"),
    "kindLink": MessageLookupByLibrary.simpleMessage("лінк"),
    "kindLogic": MessageLookupByLibrary.simpleMessage("Логічний блок"),
    "kindMyBlock": MessageLookupByLibrary.simpleMessage("Власний блок"),
    "kindNode": MessageLookupByLibrary.simpleMessage("вузол"),
    "kindSink": MessageLookupByLibrary.simpleMessage("Вихід"),
    "kindStorage": MessageLookupByLibrary.simpleMessage("сховище"),
    "kindTreeNode": MessageLookupByLibrary.simpleMessage("Вузол дерева"),
    "lag": m198,
    "languageName": MessageLookupByLibrary.simpleMessage("Українська"),
    "lastRead": m199,
    "legendCommands": MessageLookupByLibrary.simpleMessage("команди"),
    "legendConnected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "legendFree": MessageLookupByLibrary.simpleMessage("вільне поле"),
    "legendNote": MessageLookupByLibrary.simpleMessage(
      "Анімація — лише прикраса; вона зупиняється, коли система просить менше руху.",
    ),
    "legendOffline": MessageLookupByLibrary.simpleMessage("офлайн"),
    "legendPlatform": MessageLookupByLibrary.simpleMessage("платформа"),
    "legendReadOnly": MessageLookupByLibrary.simpleMessage(
      "без лівого порту = точка лише для читання",
    ),
    "legendReads": MessageLookupByLibrary.simpleMessage("читає значення"),
    "legendValues": MessageLookupByLibrary.simpleMessage("потік значень"),
    "legendWaiting": MessageLookupByLibrary.simpleMessage("чекає в карантині"),
    "legendWrites": MessageLookupByLibrary.simpleMessage("пише в пристрій"),
    "letItIn": MessageLookupByLibrary.simpleMessage("Допустити"),
    "letOthersIn": MessageLookupByLibrary.simpleMessage("Допустити інших"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Допустити брокер"),
    "levelConfig": MessageLookupByLibrary.simpleMessage("налаштування"),
    "levelList": MessageLookupByLibrary.simpleMessage("перелік"),
    "levelNone": MessageLookupByLibrary.simpleMessage("немає"),
    "levelRead": MessageLookupByLibrary.simpleMessage("читання"),
    "levelWrite": MessageLookupByLibrary.simpleMessage("запис"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkCategoryApps": MessageLookupByLibrary.simpleMessage("Застосунки"),
    "linkCategoryEquipment": MessageLookupByLibrary.simpleMessage("Обладнання"),
    "linkCategoryFileStores": MessageLookupByLibrary.simpleMessage(
      "Сховища файлів",
    ),
    "linkCategoryHistorySync": MessageLookupByLibrary.simpleMessage(
      "Синхронізація історії",
    ),
    "linkCategoryMessaging": MessageLookupByLibrary.simpleMessage(
      "Повідомлення",
    ),
    "linkCategoryPackages": MessageLookupByLibrary.simpleMessage("Пакети"),
    "linkCategoryTest": MessageLookupByLibrary.simpleMessage("Тест"),
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linkSummaryAgent": MessageLookupByLibrary.simpleMessage(
      "Планує зміни, які схвалює людина",
    ),
    "linkSummaryAlarm": MessageLookupByLibrary.simpleMessage(
      "Класи тривог, записи й підтвердження",
    ),
    "linkSummaryBacnet": MessageLookupByLibrary.simpleMessage(
      "Who-Is/I-Am, RPM, BBMD, маршрутизовані пристрої",
    ),
    "linkSummaryDlms": MessageLookupByLibrary.simpleMessage(
      "Лічильники електроенергії",
    ),
    "linkSummaryDql": MessageLookupByLibrary.simpleMessage(
      "Таблиці з дерева, як запити DSA",
    ),
    "linkSummaryDynamodb": MessageLookupByLibrary.simpleMessage(
      "Рядки історії з TTL",
    ),
    "linkSummaryGdrive": MessageLookupByLibrary.simpleMessage(
      "Тека або спільний диск",
    ),
    "linkSummaryHttp": MessageLookupByLibrary.simpleMessage(
      "JSON API, які опитуються за розкладом",
    ),
    "linkSummaryInfluxdb": MessageLookupByLibrary.simpleMessage(
      "Line protocol, теги site і key",
    ),
    "linkSummaryLocalfs": MessageLookupByLibrary.simpleMessage(
      "Каталог хоста, USB/SD або змонтований том",
    ),
    "linkSummaryMock": MessageLookupByLibrary.simpleMessage(
      "Згенеровані точки для тестів і вимірювань",
    ),
    "linkSummaryMockdev": MessageLookupByLibrary.simpleMessage(
      "Імітований пристрій на каркасі драйверів",
    ),
    "linkSummaryModbus": MessageLookupByLibrary.simpleMessage(
      "TCP, RTU через TCP, послідовний RTU · master і slave",
    ),
    "linkSummaryMongodb": MessageLookupByLibrary.simpleMessage(
      "Рядки історії як документи",
    ),
    "linkSummaryMqtt": MessageLookupByLibrary.simpleMessage("Теми як точки"),
    "linkSummaryMysql": MessageLookupByLibrary.simpleMessage(
      "Рядки історії одним upsert на пакет",
    ),
    "linkSummaryOpcua": MessageLookupByLibrary.simpleMessage(
      "Вузли серверів OPC UA як точки",
    ),
    "linkSummaryPostgres": MessageLookupByLibrary.simpleMessage(
      "Надсилає журнал історії до бази даних",
    ),
    "linkSummaryPrometheus": MessageLookupByLibrary.simpleMessage(
      "Збирає метрики експортерів у точки",
    ),
    "linkSummaryS3": MessageLookupByLibrary.simpleMessage(
      "Бакет як дерево тек і файлів",
    ),
    "linkSummaryS7": MessageLookupByLibrary.simpleMessage(
      "S7-300/400/1200/1500 через ISO-on-TCP",
    ),
    "linkSummaryScheduler": MessageLookupByLibrary.simpleMessage(
      "Тижневі розклади й особливі дні",
    ),
    "linkSummarySnmp": MessageLookupByLibrary.simpleMessage("Агенти v2c і v3"),
    "linkSummaryUplink": MessageLookupByLibrary.simpleMessage(
      "MQTT, Sparkplug, ThingsBoard, Azure, AWS",
    ),
    "linkSummaryWebdav": MessageLookupByLibrary.simpleMessage(
      "Nextcloud, ownCloud та інші сервери WebDAV",
    ),
    "linkTitleAgent": MessageLookupByLibrary.simpleMessage("Агент-асистент"),
    "linkTitleAlarm": MessageLookupByLibrary.simpleMessage("Тривоги"),
    "linkTitleBacnet": MessageLookupByLibrary.simpleMessage("BACnet/IP"),
    "linkTitleDlms": MessageLookupByLibrary.simpleMessage("DLMS/COSEM"),
    "linkTitleDql": MessageLookupByLibrary.simpleMessage("Запити DQL"),
    "linkTitleDynamodb": MessageLookupByLibrary.simpleMessage("DynamoDB"),
    "linkTitleGdrive": MessageLookupByLibrary.simpleMessage("Google Drive"),
    "linkTitleHttp": MessageLookupByLibrary.simpleMessage("HTTP / REST"),
    "linkTitleInfluxdb": MessageLookupByLibrary.simpleMessage(
      "InfluxDB 2.x / 3.x",
    ),
    "linkTitleLocalfs": MessageLookupByLibrary.simpleMessage("Локальна тека"),
    "linkTitleMock": MessageLookupByLibrary.simpleMessage("Mock"),
    "linkTitleMockdev": MessageLookupByLibrary.simpleMessage(
      "Імітований пристрій",
    ),
    "linkTitleModbus": MessageLookupByLibrary.simpleMessage("Modbus"),
    "linkTitleMongodb": MessageLookupByLibrary.simpleMessage("MongoDB"),
    "linkTitleMqtt": MessageLookupByLibrary.simpleMessage("MQTT"),
    "linkTitleMysql": MessageLookupByLibrary.simpleMessage("MySQL / MariaDB"),
    "linkTitleOpcua": MessageLookupByLibrary.simpleMessage("Клієнт OPC UA"),
    "linkTitlePostgres": MessageLookupByLibrary.simpleMessage(
      "PostgreSQL / TimescaleDB",
    ),
    "linkTitlePrometheus": MessageLookupByLibrary.simpleMessage("Prometheus"),
    "linkTitleS3": MessageLookupByLibrary.simpleMessage("S3 і сумісні"),
    "linkTitleS7": MessageLookupByLibrary.simpleMessage("Siemens S7"),
    "linkTitleScheduler": MessageLookupByLibrary.simpleMessage("Планувальник"),
    "linkTitleSnmp": MessageLookupByLibrary.simpleMessage("SNMP"),
    "linkTitleUplink": MessageLookupByLibrary.simpleMessage(
      "Платформи верхнього рівня",
    ),
    "linkTitleWebdav": MessageLookupByLibrary.simpleMessage("WebDAV"),
    "linksAlready": m200,
    "linksCount": m201,
    "linksLocalNote": m202,
    "linksOn": m203,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "listAnd": m204,
    "listFailedTip": m205,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "Ви не можете читати всі джерела й цілі цього потоку",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "lockKept": m206,
    "lockRefused": m207,
    "lockText": m208,
    "lockTitle": MessageLookupByLibrary.simpleMessage("Studio заблоковано"),
    "lockUnlock": MessageLookupByLibrary.simpleMessage("Відімкнути"),
    "lockWrongPassword": MessageLookupByLibrary.simpleMessage(
      "Пароль неправильний.",
    ),
    "logEmpty": MessageLookupByLibrary.simpleMessage("Рядків немає."),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInLead": MessageLookupByLibrary.simpleMessage(
      "до gateway брокера. Ваша роль там визначає, що ви можете змінювати.",
    ),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть у gateway WYRM.",
    ),
    "logOf": m209,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "lookAgain": MessageLookupByLibrary.simpleMessage("Шукати ще"),
    "mAclDenials": MessageLookupByLibrary.simpleMessage("Відмови ACL"),
    "mAuditRecords": MessageLookupByLibrary.simpleMessage("Записи аудиту"),
    "mFreeDisk": MessageLookupByLibrary.simpleMessage("Вільний диск"),
    "mInQuarantine": MessageLookupByLibrary.simpleMessage("У карантині"),
    "mLinksConnected": MessageLookupByLibrary.simpleMessage(
      "Лінків під’єднано",
    ),
    "mMemory": MessageLookupByLibrary.simpleMessage("Пам’ять"),
    "mSessions": MessageLookupByLibrary.simpleMessage("Сесії"),
    "mStandby": MessageLookupByLibrary.simpleMessage("Резерв"),
    "mUpDown": MessageLookupByLibrary.simpleMessage("Верхні / нижні"),
    "manifest": MessageLookupByLibrary.simpleMessage("Маніфест"),
    "mayDoEditNote": MessageLookupByLibrary.simpleMessage(
      "Це параметри лінка агента (потрібен config). Вибір додається до змін і виконується, коли ви застосуєте його в Review. Зміна адреси, куди надсилається ключ, видаляє ключ; потім введіть його знову.",
    ),
    "mayDoModes": MessageLookupByLibrary.simpleMessage("Хто схвалює"),
    "mayDoNote": MessageLookupByLibrary.simpleMessage(
      "Це параметри самого link агента. Зміни їх у Links › Edit params.",
    ),
    "mbBackFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу повернися до флоу",
    ),
    "mbDelete": MessageLookupByLibrary.simpleMessage("Видалити"),
    "mbEdit": MessageLookupByLibrary.simpleMessage("Редагувати власний блок"),
    "mbInUse": m210,
    "mbInsideItself": MessageLookupByLibrary.simpleMessage(
      "Блок не може містити сам себе",
    ),
    "mbLibraryBusy": MessageLookupByLibrary.simpleMessage(
      "Чекаємо на відповідь бібліотеки",
    ),
    "mbNotInLibrary": MessageLookupByLibrary.simpleMessage(
      "У бібліотеці немає блока з такою назвою",
    ),
    "mbRemoveLibrary": MessageLookupByLibrary.simpleMessage(
      "Видалити з бібліотеки",
    ),
    "mbRename": MessageLookupByLibrary.simpleMessage("Перейменувати"),
    "mbSameVersion": MessageLookupByLibrary.simpleMessage(
      "Флоу має версію з бібліотеки",
    ),
    "mbSave": MessageLookupByLibrary.simpleMessage("Зберегти в бібліотеку"),
    "mbUpdate": MessageLookupByLibrary.simpleMessage("Оновити з бібліотеки"),
    "mbUpdateTo": m211,
    "mbUsed": m212,
    "mbVersion": m213,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Мова"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Інше"),
    "menuSubtitle": m214,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Тема"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Повідомлень роутера за секунду",
    ),
    "metaFailedTip": m215,
    "modeConfig": MessageLookupByLibrary.simpleMessage("Лише кроки config"),
    "modeConfigDetail": MessageLookupByLibrary.simpleMessage(
      "Кроки запису виконуються одразу власним ключем агента; кроки config чекають на людину.",
    ),
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Вбудований"),
    "modeEmbeddedNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера: найлегший; зупиняється разом із брокером.",
    ),
    "modeExternal": MessageLookupByLibrary.simpleMessage("Зовнішній"),
    "modeExternalNote": MessageLookupByLibrary.simpleMessage(
      "На іншій машині: під’єднується із сертифікатом цього сайту.",
    ),
    "modeNever": MessageLookupByLibrary.simpleMessage(
      "Ніколи — кроки запису виконуються одразу; кроки config і далі чекають на людину",
    ),
    "modeNeverDetail": MessageLookupByLibrary.simpleMessage(
      "Агент виконує кроки config лише з токеном людини, як у «Лише кроки config». Текст у дереві може керувати планом.",
    ),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Процес"),
    "modeProcessNote": MessageLookupByLibrary.simpleMessage(
      "Окремий процес на цьому хості; брокер стежить і перезапускає.",
    ),
    "modeUnknown": MessageLookupByLibrary.simpleMessage("Невідомо"),
    "modeUnknownCaution": MessageLookupByLibrary.simpleMessage(
      "Невідомо, хто схвалює (налаштування агента не вдалося прочитати): план вибраного варіанта може виконати кроки запису без людини. Мітка — здогад асистента, а не перевірка. Прочитайте плитку, перш ніж вибрати її.",
    ),
    "modeUnknownDetail": MessageLookupByLibrary.simpleMessage(
      "Налаштування агента не вдалося прочитати, тому невідомо, хто схвалює.",
    ),
    "modeWasm": MessageLookupByLibrary.simpleMessage("WASM"),
    "modeWasmNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера в пісочниці: без файлів, лише дозволена мережа, обмеження пам’яті й часу. Визначається типом пакета.",
    ),
    "modeWrite": MessageLookupByLibrary.simpleMessage("Кожен крок"),
    "modeWriteDetail": MessageLookupByLibrary.simpleMessage(
      "Людина схвалює кожен set та invoke. Рекомендовано.",
    ),
    "modelReviewed": MessageLookupByLibrary.simpleMessage(
      "що асистент прочитав про це",
    ),
    "modelSays": MessageLookupByLibrary.simpleMessage("асистент каже"),
    "monthsShort": MessageLookupByLibrary.simpleMessage(
      "січ,лют,бер,кві,тра,чер,лип,сер,вер,жов,лис,гру",
    ),
    "more": MessageLookupByLibrary.simpleMessage("Ще"),
    "moreButton": m216,
    "moreBytes": m217,
    "moreLines": m218,
    "moreNone": MessageLookupByLibrary.simpleMessage(
      "Позначте вузли, для яких потрібен план.",
    ),
    "moreNote": MessageLookupByLibrary.simpleMessage(
      "Рядки запропонував асистент. Його план для них чекає на ваше схвалення.",
    ),
    "myBlocksEmpty": MessageLookupByLibrary.simpleMessage(
      "Власних блоків ще немає. Вибери блоки на полотні та натисни «Створити власний блок…» у їхньому меню.",
    ),
    "myBlocksLibrary": MessageLookupByLibrary.simpleMessage("Бібліотека сайту"),
    "myBlocksOff": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має власних блоків: його рушій флоу старший за ADR 0040.",
    ),
    "myBlocksReason": MessageLookupByLibrary.simpleMessage(
      "Потрібні власні блоки в рушії",
    ),
    "myBlocksThisFlow": MessageLookupByLibrary.simpleMessage("Цей флоу"),
    "nSelected": m219,
    "nameIt": MessageLookupByLibrary.simpleMessage("Дайте лінку назву."),
    "nameRule": MessageLookupByLibrary.simpleMessage(
      "Літери, цифри, . _ - · не зайнята іншим лінком, видаленим лінком або сайтом",
    ),
    "nameTaken": MessageLookupByLibrary.simpleMessage(
      "Ця назва вже є в іншого лінка.",
    ),
    "needsConfigOnSys": MessageLookupByLibrary.simpleMessage(
      "Потрібен config на sys",
    ),
    "needsLevelOn": m220,
    "needsLevelYouHave": m221,
    "needsLevelYouHaveIt": m222,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newCertificate": MessageLookupByLibrary.simpleMessage("новий сертифікат"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("Новий потік"),
    "newTask": MessageLookupByLibrary.simpleMessage("Нова задача"),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "no": MessageLookupByLibrary.simpleMessage("ні"),
    "noActionReason": m223,
    "noAgent": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті немає асистента. Асистент — це link агента: додай його, дай йому API-ключ і питай тут.",
    ),
    "noAudit": MessageLookupByLibrary.simpleMessage(
      "Немає записів аудиту, доступних вам.",
    ),
    "noAuditHere": MessageLookupByLibrary.simpleMessage(
      "Немає записів для цього вузла серед останніх 500 у sys/audit.",
    ),
    "noChildren": MessageLookupByLibrary.simpleMessage(
      "Під цим вузлом нічого немає.",
    ),
    "noEditReason": MessageLookupByLibrary.simpleMessage(
      "Ця точка не має дії edit.",
    ),
    "noFlows": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті ще немає потоків.",
    ),
    "noGrants": MessageLookupByLibrary.simpleMessage(
      "Немає дозволів, доступних вам.",
    ),
    "noHistory": MessageLookupByLibrary.simpleMessage(
      "Немає записаних значень у цьому проміжку. Точку записує спостереження в sys/history.",
    ),
    "noHistoryAction": MessageLookupByLibrary.simpleMessage(
      "Запис точки налаштовується в Історії (групи спостереження).",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "На цьому брокері ще немає лінків. Додайте лінк, щоб під’єднати пристрій.",
    ),
    "noParamReason": m224,
    "noPingReason": MessageLookupByLibrary.simpleMessage(
      "Цей вузол не має дії ping: драйвер пінгує сам (cfg ping).",
    ),
    "noPoints": MessageLookupByLibrary.simpleMessage(
      "Тут немає значень. Відкрийте гілку в дереві.",
    ),
    "noPointsYet": MessageLookupByLibrary.simpleMessage("Ще немає точок"),
    "noProfileReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має дії, що застосовує профіль до пристрою.",
    ),
    "noReadFlow": MessageLookupByLibrary.simpleMessage(
      "Щоб відкрити редактор, потрібне право read на цей потік.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "Жоден пристрій не під’єднаний як зовнішній лінк.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("Ревізій немає."),
    "noTasks": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну. Агент читає дерево, пише план і чекає схвалення. Нічого не зміниться без твого схвалення.",
    ),
    "noUpstream": m225,
    "noUsers": MessageLookupByLibrary.simpleMessage(
      "Немає користувачів, доступних вам.",
    ),
    "noValue": MessageLookupByLibrary.simpleMessage("немає значення"),
    "noWatchGroups": MessageLookupByLibrary.simpleMessage(
      "Груп спостереження ще немає. Додайте, щоб записувати точки.",
    ),
    "noWatchPaths": MessageLookupByLibrary.simpleMessage(
      "У цій групі немає точок.",
    ),
    "none": MessageLookupByLibrary.simpleMessage("немає"),
    "noneAsked": MessageLookupByLibrary.simpleMessage("не запитано"),
    "notApplied": MessageLookupByLibrary.simpleMessage("не застосовано"),
    "notBound": MessageLookupByLibrary.simpleMessage("не зв’язано"),
    "notDeployed": MessageLookupByLibrary.simpleMessage("не розгорнуто"),
    "notInstalled": MessageLookupByLibrary.simpleMessage(
      "Брокер не встановив його.",
    ),
    "notRecorded": MessageLookupByLibrary.simpleMessage("не записується"),
    "notWritable": MessageLookupByLibrary.simpleMessage(
      "Лише читання: драйвер не приймає тут значення.",
    ),
    "noteAction": MessageLookupByLibrary.simpleMessage(
      "Перетягнута з дерева. Запускається, коли run when стає true.",
    ),
    "noteActionBlock": MessageLookupByLibrary.simpleMessage(
      "Дія з дерева. Запускається за тригером, за зміною аргументу, за періодом або кнопкою «Запустити».",
    ),
    "noteBlockInputs": MessageLookupByLibrary.simpleMessage(
      "Що блок приймає. Перетягни дріт від входу до кожного внутрішнього поля, яке він живить; тут введи його значення за замовчуванням. + додає вхід.",
    ),
    "noteBlockOutputs": MessageLookupByLibrary.simpleMessage(
      "Що блок віддає. Перетягни внутрішній вихід на кожен. + додає вихід.",
    ),
    "noteKnownAs": m226,
    "noteNew": MessageLookupByLibrary.simpleMessage(
      "власний CA · перевірте код, перш ніж довіряти",
    ),
    "notePinned": m227,
    "notePlain": MessageLookupByLibrary.simpleMessage(
      "простий http на цьому комп’ютері",
    ),
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "Точка дерева. Точка лише для читання не має входу; зв’язок у записувану точку пише ~set.",
    ),
    "noteTrusted": MessageLookupByLibrary.simpleMessage(
      "цей комп’ютер довіряє сертифікату",
    ),
    "noteWyrmd": m228,
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "У карантині нічого не чекає.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Нічого не підготовлено. Змініть значення або параметр.",
    ),
    "nothingToDeploy": MessageLookupByLibrary.simpleMessage(
      "Нічого розгортати",
    ),
    "now": MessageLookupByLibrary.simpleMessage("зараз"),
    "officialList": MessageLookupByLibrary.simpleMessage("Офіційний список"),
    "officialListNote": MessageLookupByLibrary.simpleMessage(
      "Драйвери у wyrmd і пакети з вашого репозиторію. Оберіть, де працюватиме, і встановіть.",
    ),
    "officialMark": MessageLookupByLibrary.simpleMessage("офіційний"),
    "offline": MessageLookupByLibrary.simpleMessage(
      "З’єднання з gateway втрачено. Перепідключення; на екрані останні отримані значення.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "onOtherDevices": MessageLookupByLibrary.simpleMessage(
      "На інших пристроях",
    ),
    "onThisBroker": MessageLookupByLibrary.simpleMessage("На цьому брокері"),
    "onWhichBroker": MessageLookupByLibrary.simpleMessage("На якому брокері"),
    "openFull": MessageLookupByLibrary.simpleMessage("Відкрити повністю"),
    "openInExplorer": MessageLookupByLibrary.simpleMessage("Відкрити в дереві"),
    "openInLinks": MessageLookupByLibrary.simpleMessage("Відкрити в Лінках"),
    "openInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Доступи, відкликання і видалення — у Лінках › На інших пристроях.",
    ),
    "openInside": MessageLookupByLibrary.simpleMessage("Відкрити вміст"),
    "openItsTree": MessageLookupByLibrary.simpleMessage("Відкрити його дерево"),
    "openItsTreeNote": m229,
    "openNodeInExplorer": m230,
    "openReplacement": m231,
    "openSettings": MessageLookupByLibrary.simpleMessage("Відкрити параметри"),
    "openingTree": MessageLookupByLibrary.simpleMessage("Відкриваємо дерево"),
    "openingTreeOf": m232,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "osAndroid": MessageLookupByLibrary.simpleMessage("Android"),
    "osIos": MessageLookupByLibrary.simpleMessage("iOS"),
    "osLinux": MessageLookupByLibrary.simpleMessage("Linux"),
    "osMac": MessageLookupByLibrary.simpleMessage("macOS"),
    "osUnknown": MessageLookupByLibrary.simpleMessage("невідома"),
    "osWeb": MessageLookupByLibrary.simpleMessage("веб"),
    "osWindows": MessageLookupByLibrary.simpleMessage("Windows"),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m233,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "pairsCount": m234,
    "paletteBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "paletteMyBlocks": MessageLookupByLibrary.simpleMessage("Мої блоки"),
    "paletteTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "panelCanvas": MessageLookupByLibrary.simpleMessage("полотно редактора"),
    "panelDrawer": MessageLookupByLibrary.simpleMessage("бічна панель"),
    "panelInspector": MessageLookupByLibrary.simpleMessage("інспектор"),
    "panelMayDo": MessageLookupByLibrary.simpleMessage("Що йому можна"),
    "panelThisTask": MessageLookupByLibrary.simpleMessage("Ця задача"),
    "panelTree": MessageLookupByLibrary.simpleMessage("дерево"),
    "panelWorkspace": MessageLookupByLibrary.simpleMessage("робоча область"),
    "paramCount": m235,
    "paramsJson": m236,
    "paramsNotJson": m237,
    "paramsNotObject": MessageLookupByLibrary.simpleMessage(
      "Параметри мають бути одним об’єктом JSON.",
    ),
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "~meta вузла, як його оголошує брокер: профіль, cfg і attr.",
    ),
    "paramsStaged": MessageLookupByLibrary.simpleMessage(
      "Зміну параметрів агента підготовлено. Вона виконається, коли ви застосуєте її в Review.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("пройшов"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "passwordBlank": MessageLookupByLibrary.simpleMessage(
      "Пароль не може бути порожнім або лише з пробілів.",
    ),
    "pickAPoint": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку в таблиці, щоб побачити її історію.",
    ),
    "pickKeyFull": m238,
    "pickKeyHint": m239,
    "pickKeyOutside": m240,
    "pickKeySelected": MessageLookupByLibrary.simpleMessage(
      "вибрано в Explorer",
    ),
    "pickKeyTyped": m241,
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
    "pickPointHint": MessageLookupByLibrary.simpleMessage(
      "Клацніть точку, щоб побачити її тренд; ⌘/Ctrl-клацання додає до трьох.",
    ),
    "pickPointTrend": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку, щоб побачити її тренд",
    ),
    "pickedFrom": m242,
    "pickedWithStandby": m243,
    "pinField": MessageLookupByLibrary.simpleMessage("Закріпити на блоці"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле лишається на блоці",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Пінг"),
    "planCard": MessageLookupByLibrary.simpleMessage("План"),
    "planChecked": MessageLookupByLibrary.simpleMessage(
      "чекає на схвалення · перевірено",
    ),
    "planCheckedPartly": m244,
    "planNeedsStep": m245,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "План записаний у задачі. Studio покаже його, коли gateway зможе читати документи (docs/studio.md §10 п. 11). Поки що читай план через wyrm-agent.",
    ),
    "planSaved": m246,
    "planSavedSecrets": m247,
    "planSavedStep": m248,
    "planSecretNote": MessageLookupByLibrary.simpleMessage(
      "Секретний аргумент не показано. Схвалення все одно стосується значення, яке тримає план.",
    ),
    "planSleep": m249,
    "planSteps": m250,
    "planTimeout": m251,
    "planWaiting": MessageLookupByLibrary.simpleMessage(
      "План чекає на схвалення. До нього нічого не виконується.",
    ),
    "planWhyNote": MessageLookupByLibrary.simpleMessage(
      "Рядки після «why» і під «асистент каже» пише модель; попередження на жовтій смузі — власна перевірка лінка. Прочитай ключ і аргументи кожного кроку: виконується саме це.",
    ),
    "platform": MessageLookupByLibrary.simpleMessage("Платформа"),
    "platformNote": MessageLookupByLibrary.simpleMessage(
      "Його налаштування і лічильники — у downstream/uplink.",
    ),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Перевірте налаштування мережі.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Увійдіть ще раз.",
    ),
    "pointR": MessageLookupByLibrary.simpleMessage("R"),
    "pointRw": MessageLookupByLibrary.simpleMessage("RW"),
    "pointsCount": m252,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується в пристрій до застосування.",
    ),
    "portBad": MessageLookupByLibrary.simpleMessage("Порт — від 1 до 65535."),
    "portsCount": m253,
    "prefixesLabel": MessageLookupByLibrary.simpleMessage(
      "Де він може пропонувати зміни",
    ),
    "prefixesNote": MessageLookupByLibrary.simpleMessage(
      "allowed_prefixes · поза ними крок відхиляє перевірка.",
    ),
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Читання блоків потоків",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Читання потоків"),
    "preloadLater": m254,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Читання лінків"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Читання сайтів"),
    "preloadTree": m255,
    "previewInvalid": m256,
    "previewTag": MessageLookupByLibrary.simpleMessage("перегляд"),
    "probeButton": MessageLookupByLibrary.simpleMessage("Перевірити"),
    "probeNote": MessageLookupByLibrary.simpleMessage(
      "Один запит HTTPS до /api/info на кожну адресу, 16 одночасно, не більше 1024 адрес. Спитайте дозволу, перш ніж перевіряти чужу мережу.",
    ),
    "probePortField": MessageLookupByLibrary.simpleMessage("Порт"),
    "probeRangeField": MessageLookupByLibrary.simpleMessage("Діапазон"),
    "probeRangeTitle": MessageLookupByLibrary.simpleMessage(
      "Перевірити діапазон",
    ),
    "problemCodeMismatch": MessageLookupByLibrary.simpleMessage(
      "Недоступно: оголошений код CA не збігається з кодом його CA.",
    ),
    "problemInvalid": MessageLookupByLibrary.simpleMessage("недійсний"),
    "problemNoAnswer": m257,
    "problemNoCa": MessageLookupByLibrary.simpleMessage(
      "Недоступно: цей комп’ютер не довіряє сертифікату, а CA для перевірки gateway не надсилає.",
    ),
    "problemNoInfo": MessageLookupByLibrary.simpleMessage(
      "Недоступно: цей wyrmd старіший, ніж потрібно Studio (немає /api/info).",
    ),
    "problemNoName": MessageLookupByLibrary.simpleMessage(
      "Недоступно: сертифікат не називає ні цю адресу, ні ім’я хоста. Введіть адресу.",
    ),
    "problemPlainHttp": MessageLookupByLibrary.simpleMessage(
      "Недоступно: простий http поза цим комп’ютером заборонено (insecure_plaintext).",
    ),
    "problemStudioTooOld": m258,
    "problemUnnamed": MessageLookupByLibrary.simpleMessage("назвіть потік"),
    "problems": MessageLookupByLibrary.simpleMessage("Проблеми"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Очистити все"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Закрити проблеми"),
    "problemsCount": m259,
    "problemsEmpty": MessageLookupByLibrary.simpleMessage(
      "У цьому сеансі проблем немає.",
    ),
    "problemsNote": MessageLookupByLibrary.simpleMessage(
      "Збої того, що Studio робила сама (читання, оновлення, живі значення), і кожен закритий діалог. Зберігаються до закриття Studio; найновіші зверху.",
    ),
    "problemsShown": MessageLookupByLibrary.simpleMessage("показано як діалог"),
    "problemsTitle": MessageLookupByLibrary.simpleMessage(
      "Проблеми · цей сеанс",
    ),
    "purgeHistory": MessageLookupByLibrary.simpleMessage(
      "Видалити проміжок часу",
    ),
    "purgeHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Видаляє записані рядки проміжку для всіх точок.",
    ),
    "qCheckFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку",
    ),
    "qCheckOk": MessageLookupByLibrary.simpleMessage(
      "Пакет виглядає правильно",
    ),
    "qChoose": MessageLookupByLibrary.simpleMessage("Що ви хочете додати?"),
    "qFailed": MessageLookupByLibrary.simpleMessage("Брокер не встановив його"),
    "qInstalled": m260,
    "qInstalling": m261,
    "qRun": MessageLookupByLibrary.simpleMessage(
      "Де він працюватиме і під якою назвою?",
    ),
    "qualityBad": MessageLookupByLibrary.simpleMessage("погана"),
    "qualityGood": MessageLookupByLibrary.simpleMessage("добра"),
    "qualityUncertain": MessageLookupByLibrary.simpleMessage("невизначена"),
    "quarantine": MessageLookupByLibrary.simpleMessage("Карантин"),
    "quarantineAndAdmission": MessageLookupByLibrary.simpleMessage(
      "Карантин і допуск",
    ),
    "quarantineAndAdmissionNote": MessageLookupByLibrary.simpleMessage(
      "Невідомі сертифікати чекають у Лінках › Карантин.",
    ),
    "rangeBadPart": MessageLookupByLibrary.simpleMessage(
      "Кожна частина адреси — від 0 до 255.",
    ),
    "rangeBadPrefix": MessageLookupByLibrary.simpleMessage(
      "Префікс — від 0 до 32.",
    ),
    "rangeBadText": MessageLookupByLibrary.simpleMessage(
      "Введіть діапазон IPv4, наприклад 10.0.7.0/24.",
    ),
    "rangeTooBig": MessageLookupByLibrary.simpleMessage(
      "Не більше 1024 адрес: /22 або менше.",
    ),
    "reachesSites": m262,
    "readAgain": MessageLookupByLibrary.simpleMessage("Прочитати знову"),
    "readFailed": MessageLookupByLibrary.simpleMessage("не прочитано"),
    "readFailedTip": m263,
    "readsNote": MessageLookupByLibrary.simpleMessage(
      "Читання не потребує схвалення. Агент читає лише в межах ваших прав і своїх.",
    ),
    "recordInHistory": MessageLookupByLibrary.simpleMessage(
      "Записувати в історію…",
    ),
    "recorded": MessageLookupByLibrary.simpleMessage("записується"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "refusalBadPassword": MessageLookupByLibrary.simpleMessage(
      "пароль неправильний",
    ),
    "refusalConfirmRequired": MessageLookupByLibrary.simpleMessage(
      "він спершу просить підтвердження",
    ),
    "refusalDeviceRemoved": MessageLookupByLibrary.simpleMessage(
      "цей пристрій видалено",
    ),
    "refusalDevicesOff": MessageLookupByLibrary.simpleMessage(
      "відмикання пристроєм на цьому шлюзі вимкнено",
    ),
    "refusalPasswordChanged": MessageLookupByLibrary.simpleMessage(
      "пароль змінено",
    ),
    "refusalPasswordDue": MessageLookupByLibrary.simpleMessage(
      "час знову ввести пароль",
    ),
    "refusalPasswordRequired": MessageLookupByLibrary.simpleMessage(
      "він спершу просить пароль",
    ),
    "refusalTooManyDevices": MessageLookupByLibrary.simpleMessage(
      "у цього користувача забагато пристроїв",
    ),
    "refuseLoop": MessageLookupByLibrary.simpleMessage(
      "Це замикає цикл (лише через delay)",
    ),
    "refuseNeedsBroker": m264,
    "refuseNoInput": m265,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Вихід не можна зв’язати",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "Блок не може живити сам себе",
    ),
    "refuseType": m266,
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Причина"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "План не виконується. Причина зберігається в записі завдання.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Відхилити план?"),
    "rejectTitle": m267,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Звідси нічого робити: він прийшов разом зі своїм ретранслятором. Відкличте ретранслятор, щоб відрізати його.",
    ),
    "relaysSites": m268,
    "rememberGatewayAndUser": MessageLookupByLibrary.simpleMessage(
      "Запам’ятати gateway і користувача на цьому комп’ютері",
    ),
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "Якщо пристрій втрачено або вкрадено: «Видалити назавжди». Відкликання — це пауза: схваліть знову з карантину, і він збереже ім’я та дерево.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "removeBlock": MessageLookupByLibrary.simpleMessage("Видалити блок"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено. Ім’я можна використати знову.",
    ),
    "removeEllipsis": MessageLookupByLibrary.simpleMessage("Видалити…"),
    "removeGroup": MessageLookupByLibrary.simpleMessage("Видалити групу"),
    "removeGroupNote": MessageLookupByLibrary.simpleMessage(
      "Запис зупиниться; рядки лишаються, якщо не видалити їх.",
    ),
    "removeInput": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній вхід",
    ),
    "removeLinkTitle": m269,
    "removePair": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній випадок",
    ),
    "removePort": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній порт",
    ),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено, а id вилучено: його не можна використати знову.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Видалити користувача"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "Він більше не зможе увійти; його сесії завершаться.",
    ),
    "removeUserTitle": m270,
    "replacedNote": m271,
    "replacedTitle": MessageLookupByLibrary.simpleMessage("замінено"),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultNoValue": MessageLookupByLibrary.simpleMessage("—"),
    "resultNote": MessageLookupByLibrary.simpleMessage(
      "Ключі, яких торкнувся план, з їхніми значеннями зараз.",
    ),
    "resultOf": m272,
    "resultTitle": MessageLookupByLibrary.simpleMessage("Результат"),
    "returns": m273,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "reviewNote": m274,
    "reviewingNote": MessageLookupByLibrary.simpleMessage(
      "Асистент читає, чому виконання зупинилось…",
    ),
    "revision": m275,
    "revisionNow": m276,
    "rightCall": MessageLookupByLibrary.simpleMessage("виклик"),
    "rightMemory": MessageLookupByLibrary.simpleMessage("пам’ять"),
    "rightMib": m277,
    "rightMs": m278,
    "rightNetwork": MessageLookupByLibrary.simpleMessage("мережа"),
    "rightOn": m279,
    "rightStore": MessageLookupByLibrary.simpleMessage("сховище"),
    "rightsLine": m280,
    "rightsNone": MessageLookupByLibrary.simpleMessage("немає"),
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "roleOnSite": m281,
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m282,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Додати рядок"),
    "rowsAnswered": m283,
    "rowsEmpty": MessageLookupByLibrary.simpleMessage("Рядків ще немає"),
    "rowsRemove": MessageLookupByLibrary.simpleMessage("Прибрати цей рядок"),
    "rstAcceptLinks": MessageLookupByLibrary.simpleMessage(
      "Прийняти права й мережу, які просять лінки з файлу",
    ),
    "rstAcceptPackages": MessageLookupByLibrary.simpleMessage(
      "Прийняти права й мережу, які просять пакети з файлу",
    ),
    "rstAdd": MessageLookupByLibrary.simpleMessage(
      "Лише додати: лінки й вузли сховища, яких ще немає; нічого не замінюється, без перезапуску",
    ),
    "rstAddNote": MessageLookupByLibrary.simpleMessage("Нічого не замінюється"),
    "rstAdded": MessageLookupByLibrary.simpleMessage(
      "Додано; нічого не замінено, без перезапуску",
    ),
    "rstApplied": MessageLookupByLibrary.simpleMessage(
      "Копію застосовано; брокер працює на ній",
    ),
    "rstCheck": MessageLookupByLibrary.simpleMessage("Перевірити файл"),
    "rstChecked": MessageLookupByLibrary.simpleMessage("Перевірено"),
    "rstChoose": MessageLookupByLibrary.simpleMessage("Вибрати файл…"),
    "rstConfigNever": MessageLookupByLibrary.simpleMessage(
      "Копія для довідки; відновлення її не записує.",
    ),
    "rstConfirmKeys": MessageLookupByLibrary.simpleMessage(
      "Спершу позначте заміну ключів сайту",
    ),
    "rstControlOther": MessageLookupByLibrary.simpleMessage(
      "Площина керування не відкривається ключами цього брокера",
    ),
    "rstControlOtherNote": MessageLookupByLibrary.simpleMessage(
      "Вона відновлюється лише разом із ключами й секретами.",
    ),
    "rstDoAdd": MessageLookupByLibrary.simpleMessage("Додати"),
    "rstDoReplace": MessageLookupByLibrary.simpleMessage(
      "Відновити й перезапустити",
    ),
    "rstFactSections": MessageLookupByLibrary.simpleMessage("Секції"),
    "rstFile": m284,
    "rstFileNote": m285,
    "rstHow": MessageLookupByLibrary.simpleMessage("Як"),
    "rstInTheFile": MessageLookupByLibrary.simpleMessage("У файлі"),
    "rstKeysDiffer": MessageLookupByLibrary.simpleMessage(
      "CA цього сайту, інші файли ключів",
    ),
    "rstKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Введіть парольну фразу копії: ключі відновлюються лише з нею.",
    ),
    "rstKeysNone": MessageLookupByLibrary.simpleMessage("У файлі немає ключів"),
    "rstKeysNoneNote": MessageLookupByLibrary.simpleMessage(
      "Цей брокер зберігає власні ключі.",
    ),
    "rstKeysOther": MessageLookupByLibrary.simpleMessage("Інший CA"),
    "rstKeysOtherNote": MessageLookupByLibrary.simpleMessage(
      "Відновлення ключів змінює ідентичність сайту: лінки, оператори й сусідні брокери реєструються знову.",
    ),
    "rstKeysSame": MessageLookupByLibrary.simpleMessage("Ті самі ключі"),
    "rstKeysSameNote": MessageLookupByLibrary.simpleMessage(
      "Кожен файл ключів копії належить цьому брокеру; токени й сертифікати чинні.",
    ),
    "rstLinks": m286,
    "rstLogIn": MessageLookupByLibrary.simpleMessage("Увійти знову"),
    "rstLost": MessageLookupByLibrary.simpleMessage(
      "Брокер не повернувся для цієї сесії",
    ),
    "rstLostNote": MessageLookupByLibrary.simpleMessage(
      "Він може ще запускатися або працює з іншими ключами: після відновлення ключів і секретів ця сесія більше не належить сайту. Увійдіть знову; якщо шлюз не відповідає, перевірте брокер на хості.",
    ),
    "rstNotApplied": MessageLookupByLibrary.simpleMessage(
      "Відновлення не застосовано",
    ),
    "rstNotAppliedNote": MessageLookupByLibrary.simpleMessage(
      "Брокер повернув усе назад і працює на попередньому стані. План і причина збережені на хості в data_dir/restore.failed.",
    ),
    "rstNotInAdd": MessageLookupByLibrary.simpleMessage(
      "Додавання бере лише лінки й сховище.",
    ),
    "rstNothingTicked": MessageLookupByLibrary.simpleMessage(
      "Позначте секцію, яку бере цей режим",
    ),
    "rstOtherSite": m287,
    "rstOtherSiteNote": MessageLookupByLibrary.simpleMessage(
      "Брокер відмовляє копії з іншою назвою сайту. Спершу задайте site у wyrmd.json5 як у копії.",
    ),
    "rstPassphrase": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза копії",
    ),
    "rstPassphraseKept": MessageLookupByLibrary.simpleMessage(
      "Надсилається знову з відновленням. Studio її не зберігає.",
    ),
    "rstPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Лише для копії, запечатаної парольною фразою. Studio її не зберігає.",
    ),
    "rstPick": MessageLookupByLibrary.simpleMessage(
      "Виберіть файл .wyrm-backup.",
    ),
    "rstPickNote": MessageLookupByLibrary.simpleMessage(
      "Файл надходить до брокера частинами. Нічого не зміниться, доки ви не побачите, що брокер у ньому знайшов.",
    ),
    "rstReplace": MessageLookupByLibrary.simpleMessage(
      "Замінити позначене і один раз перезапустити брокер (спершу створюється копія того, що замінюється)",
    ),
    "rstReplaceKeys": m288,
    "rstReplaceKeysOther": MessageLookupByLibrary.simpleMessage(
      "Замінити ключі сайту іншим CA: лінки, оператори й сусідні брокери реєструються знову",
    ),
    "rstReplaceNote": MessageLookupByLibrary.simpleMessage(
      "Спершу створюється копія того, що замінюється",
    ),
    "rstReplaceProblems": MessageLookupByLibrary.simpleMessage(
      "Перевірка знайшла проблеми, які блокують заміну.",
    ),
    "rstReplaceUpstream": MessageLookupByLibrary.simpleMessage(
      "Ця сесія дістається сайту через вищий брокер: брокер відмовляє в заміні згори. Додавання доступне.",
    ),
    "rstRestarting": m289,
    "rstRestartingMore": MessageLookupByLibrary.simpleMessage(
      "Спершу створено копію того, що замінюється (pre-restore, у резервних копіях). Брокер зупиняється, і наступний старт застосовує підготовлені секції до відкриття сховищ.",
    ),
    "rstRestartingNote": MessageLookupByLibrary.simpleMessage(
      "Studio під\'єднається самостійно.",
    ),
    "rstSchemas": MessageLookupByLibrary.simpleMessage(
      "Формати сховищ відрізняються (копія → тут)",
    ),
    "rstTick": MessageLookupByLibrary.simpleMessage("позначте, що повернути"),
    "rstTitle": m290,
    "rstUnknown": MessageLookupByLibrary.simpleMessage("Брокер повернувся"),
    "rstUnknownNote": MessageLookupByLibrary.simpleMessage(
      "В аудиті ще немає ні restore_applied, ні restore_failed. Перегляньте Система › Журнал, перш ніж покладатися на відновлення.",
    ),
    "rstUploaded": MessageLookupByLibrary.simpleMessage("Файл на брокері"),
    "rstUploadedNote": MessageLookupByLibrary.simpleMessage(
      "Ще нічого не змінено. Перевірка читає маніфест і порівнює його з цим брокером.",
    ),
    "rstUploading": m291,
    "rstUploadingButton": MessageLookupByLibrary.simpleMessage("Вивантаження…"),
    "runBlock": MessageLookupByLibrary.simpleMessage("Запустити"),
    "runDraft": MessageLookupByLibrary.simpleMessage(
      "Спершу розгорни: «Запустити» діє на розгорнуту версію, а чернетка від неї відрізняється",
    ),
    "runNoBroker": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має дії trigger (його рушій флоу старший за ADR 0040)",
    ),
    "runNoInstance": MessageLookupByLibrary.simpleMessage(
      "Відкрий блок з екземпляра, щоб запустити його",
    ),
    "runNotDeployed": MessageLookupByLibrary.simpleMessage(
      "Спершу розгорни флоу",
    ),
    "runNotRun": MessageLookupByLibrary.simpleMessage("не виконано"),
    "runNow": MessageLookupByLibrary.simpleMessage("Виконати"),
    "runNowNote": m292,
    "runOff": MessageLookupByLibrary.simpleMessage("Блок вимкнено"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Запускати на кожному старті?",
    ),
    "runPassed": MessageLookupByLibrary.simpleMessage("усі кроки пройшли"),
    "runPassedIn": m293,
    "runPassedLeftOut": m294,
    "runRunning": MessageLookupByLibrary.simpleMessage("виконується…"),
    "runStopped": m295,
    "runStoppedFirst": MessageLookupByLibrary.simpleMessage(
      "зупинено · нічого не змінено",
    ),
    "runStoppedOne": m296,
    "runStopsNote": MessageLookupByLibrary.simpleMessage(
      "зупиняється на першому кроці, що не вдався",
    ),
    "runTitle": m297,
    "runTitleEnded": m298,
    "runWaiting": MessageLookupByLibrary.simpleMessage("чекає"),
    "running": MessageLookupByLibrary.simpleMessage("Працює"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "Агент працює над задачею. Скасування зупиняє її; зроблене лишається.",
    ),
    "runsOn": m299,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
    "saveAsPlan": MessageLookupByLibrary.simpleMessage("Зберегти як план"),
    "savePlanTitle": m300,
    "scAddToSelection": MessageLookupByLibrary.simpleMessage(
      "Додати до виділення або зняти",
    ),
    "scClick": MessageLookupByLibrary.simpleMessage("клік"),
    "scCopy": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "scCut": MessageLookupByLibrary.simpleMessage("Вирізати"),
    "scDelete": MessageLookupByLibrary.simpleMessage("Видалити"),
    "scDeploy": MessageLookupByLibrary.simpleMessage(
      "Розгорнути (з підтвердженням)",
    ),
    "scDoubleClick": MessageLookupByLibrary.simpleMessage("подвійний клік"),
    "scDrag": MessageLookupByLibrary.simpleMessage("тягнути"),
    "scDragEmpty": MessageLookupByLibrary.simpleMessage(
      "тягнути по порожньому полотну",
    ),
    "scDragHeader": MessageLookupByLibrary.simpleMessage("тягнути заголовок"),
    "scDuplicate": MessageLookupByLibrary.simpleMessage("Дублювати"),
    "scEscape": MessageLookupByLibrary.simpleMessage(
      "Скасувати, зняти виділення",
    ),
    "scGroupEdit": MessageLookupByLibrary.simpleMessage("Редагування"),
    "scGroupSelect": MessageLookupByLibrary.simpleMessage("Виділення"),
    "scGroupView": MessageLookupByLibrary.simpleMessage("Вигляд і потік"),
    "scHelp": MessageLookupByLibrary.simpleMessage("Ця картка"),
    "scMarquee": MessageLookupByLibrary.simpleMessage("Виділити рамкою"),
    "scMiddleDrag": MessageLookupByLibrary.simpleMessage(
      "тягнути середньою кнопкою",
    ),
    "scMoveSelection": MessageLookupByLibrary.simpleMessage(
      "Перемістити виділене",
    ),
    "scNote": MessageLookupByLibrary.simpleMessage(
      "Клавіші діють, доки фокус не в текстовому полі.",
    ),
    "scNudge": MessageLookupByLibrary.simpleMessage("Зсунути на крок сітки"),
    "scNudgeFar": MessageLookupByLibrary.simpleMessage("10 кроків"),
    "scOr": MessageLookupByLibrary.simpleMessage("або"),
    "scPan": MessageLookupByLibrary.simpleMessage("Прокрутити полотно"),
    "scPaste": MessageLookupByLibrary.simpleMessage("Вставити"),
    "scPinch": MessageLookupByLibrary.simpleMessage("щипок"),
    "scRedo": MessageLookupByLibrary.simpleMessage("Повторити дію"),
    "scScroll": MessageLookupByLibrary.simpleMessage("колесо / два пальці"),
    "scSearchPalette": MessageLookupByLibrary.simpleMessage("Знайти блок"),
    "scSelectAll": MessageLookupByLibrary.simpleMessage("Виділити все"),
    "scSpace": MessageLookupByLibrary.simpleMessage("Пробіл"),
    "scTitle": MessageLookupByLibrary.simpleMessage("Клавіатура і миша"),
    "scUnbind": MessageLookupByLibrary.simpleMessage("Розв’язати поле"),
    "scUndo": MessageLookupByLibrary.simpleMessage("Скасувати дію"),
    "scViewValue": MessageLookupByLibrary.simpleMessage(
      "Переглянути значення під вказівником",
    ),
    "scWheel": MessageLookupByLibrary.simpleMessage("колесо"),
    "scZoom": MessageLookupByLibrary.simpleMessage("Масштаб"),
    "scZoomFit": MessageLookupByLibrary.simpleMessage("Показати всі блоки"),
    "scZoomIn": MessageLookupByLibrary.simpleMessage("Збільшити"),
    "scZoomOut": MessageLookupByLibrary.simpleMessage("Зменшити"),
    "scZoomReset": MessageLookupByLibrary.simpleMessage("Масштаб 100 %"),
    "scopeEdit": MessageLookupByLibrary.simpleMessage("Змінити межі"),
    "scopeEmpty": MessageLookupByLibrary.simpleMessage(
      "Введи межі: ключ із дроту їх потребує",
    ),
    "scopeNote": MessageLookupByLibrary.simpleMessage(
      "Ключ, що приходить дротом, читається лише в цих межах. Той, хто розгортає, має читати їх усі.",
    ),
    "scopeOtherSite": MessageLookupByLibrary.simpleMessage(
      "Межі лежать у цьому сайті",
    ),
    "scopeSection": MessageLookupByLibrary.simpleMessage(
      "Межі починаються з downstream, dataflows або storage",
    ),
    "scopeSegment": MessageLookupByLibrary.simpleMessage(
      "Це не вираз ключа: сегменти з літер, цифр, _ . - або * та **",
    ),
    "scopeTitle": MessageLookupByLibrary.simpleMessage(
      "Цей блок може читати ключі в межах",
    ),
    "screenOf": m301,
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Перейти до вузла, дії або лінка",
    ),
    "searchLinks": MessageLookupByLibrary.simpleMessage("Шукати у списку"),
    "secAttributes": MessageLookupByLibrary.simpleMessage("Атрибути"),
    "secDiagnostics": MessageLookupByLibrary.simpleMessage("Діагностика"),
    "secParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "secPolling": MessageLookupByLibrary.simpleMessage("Опитування"),
    "secPublish": MessageLookupByLibrary.simpleMessage("Що опублікує дерево"),
    "secRegister": MessageLookupByLibrary.simpleMessage("Регістр"),
    "secState": MessageLookupByLibrary.simpleMessage("Стан"),
    "secValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "secWrite": MessageLookupByLibrary.simpleMessage("Запис"),
    "secretName": MessageLookupByLibrary.simpleMessage("Назва"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Значення (порожнє — видалити)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "Брокер запечатує секрет, і він більше не показується; лінк читає його за назвою.",
    ),
    "sectionEarlier": MessageLookupByLibrary.simpleMessage("Раніше"),
    "sectionNow": MessageLookupByLibrary.simpleMessage("Зараз"),
    "securityAdded": m302,
    "securityConfirm": MessageLookupByLibrary.simpleMessage(
      "Підтверджувати перед змінами config",
    ),
    "securityConfirmForced": m303,
    "securityConfirmNone": m304,
    "securityDevicesOn": m305,
    "securityDue": m306,
    "securityForget": MessageLookupByLibrary.simpleMessage("Забути"),
    "securityLockAfter": MessageLookupByLibrary.simpleMessage(
      "Блокувати Studio через",
    ),
    "securityLockDesc": m307,
    "securityLockOff": MessageLookupByLibrary.simpleMessage("Вимкнено"),
    "securityMenu": MessageLookupByLibrary.simpleMessage("Безпека"),
    "securityMinutes": m308,
    "securityNoBio": MessageLookupByLibrary.simpleMessage(
      "На цьому комп’ютері немає біометричного відмикання: він питає пароль.",
    ),
    "securityNoDevices": MessageLookupByLibrary.simpleMessage(
      "Пристроїв ще немає.",
    ),
    "securityOn": m309,
    "securityPasswordNeeded": m310,
    "securityPolicy": m311,
    "securityPolicyConfirm": MessageLookupByLibrary.simpleMessage(
      " · підтвердження змін config",
    ),
    "securityPolicyOff": MessageLookupByLibrary.simpleMessage("вимкнено"),
    "securityPolicyOn": MessageLookupByLibrary.simpleMessage("увімкнено"),
    "securityRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "securityRemoved": MessageLookupByLibrary.simpleMessage(
      "видалено · входить лише з паролем",
    ),
    "securityRemovedBy": m312,
    "securitySignOutAll": MessageLookupByLibrary.simpleMessage("Вийти всюди"),
    "securitySignOutAllNote": m313,
    "securitySignedOut": MessageLookupByLibrary.simpleMessage("вийшов"),
    "securityThisDevice": MessageLookupByLibrary.simpleMessage("цей пристрій"),
    "securityTitle": MessageLookupByLibrary.simpleMessage("Безпека"),
    "securityTurnOff": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "securityTurnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "securityUnlockDesc": m314,
    "securityUnlockOffDesc": m315,
    "securityUsedNow": MessageLookupByLibrary.simpleMessage(
      "використано зараз",
    ),
    "seeLinks": MessageLookupByLibrary.simpleMessage("див. Лінки"),
    "seenAgo": m316,
    "seenNow": MessageLookupByLibrary.simpleMessage("зараз"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setLogLevel": m317,
    "setLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Діє одразу, без перезапуску. Готується разом з іншими змінами.",
    ),
    "setPassword": MessageLookupByLibrary.simpleMessage("Задати пароль"),
    "setPasswordNote": MessageLookupByLibrary.simpleMessage(
      "Відкриті сесії лишаються до завершення.",
    ),
    "setPoll": MessageLookupByLibrary.simpleMessage("Задати опитування…"),
    "setRoles": MessageLookupByLibrary.simpleMessage("Задати ролі"),
    "setRolesNote": MessageLookupByLibrary.simpleMessage(
      "Ролі визначають, що доступно (див. Дозволи).",
    ),
    "setSecret": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "setValue": MessageLookupByLibrary.simpleMessage("Задати значення"),
    "showArgs": MessageLookupByLibrary.simpleMessage("Показати аргументи"),
    "showPassword": MessageLookupByLibrary.simpleMessage("Показати пароль"),
    "showSteps": MessageLookupByLibrary.simpleMessage("Показати кроки"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Вхід…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Сайт, ретрансльований нижче",
    ),
    "sitesAround": m318,
    "sitesSubtitle": m319,
    "sizeBytes": m320,
    "sizeChars": m321,
    "sizeColumns": m322,
    "sizeItems": m323,
    "sizeKeys": m324,
    "sizeLines": m325,
    "sizeRows": m326,
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m327,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
    "stagedWas": m328,
    "stale": MessageLookupByLibrary.simpleMessage("застаріле"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Його резервний gateway відповідає на",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "standbyIs": m329,
    "stateConnected": MessageLookupByLibrary.simpleMessage("Під’єднано"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Збій"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Встановлено"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Офлайн"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Запускається"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Зупинено"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Зупиняється"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Чекає"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Принести"),
    "stepByAgent": MessageLookupByLibrary.simpleMessage(
      "виконується ключем агента: у цьому режимі людина для нього не потрібна, і його не можна пропустити",
    ),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Перевірка"),
    "stepChecking": MessageLookupByLibrary.simpleMessage(
      "Перевірка користувача і пароля",
    ),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Вибір"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Встановлення"),
    "stepLeftOut": MessageLookupByLibrary.simpleMessage(
      "пропущено: не виконається",
    ),
    "stepOf": m330,
    "stepReaching": m331,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Читання вашої ролі та сайтів",
    ),
    "stepSkippedNeeds": m332,
    "stepUpConfirm": MessageLookupByLibrary.simpleMessage("Підтвердити"),
    "stepUpConfirmWith": m333,
    "stepUpDevice": m334,
    "stepUpKeyGone": m335,
    "stepUpLead": m336,
    "stepUpPasswordOnly": m337,
    "stepUpRefused": m338,
    "stepUpStopped": m339,
    "stepUpTitle": MessageLookupByLibrary.simpleMessage(
      "Підтвердіть, що це ви",
    ),
    "stepUpWaiting": m340,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Припинити запис"),
    "stoppedAt": m341,
    "stoppedAtCode": m342,
    "stoppedNote": m343,
    "studioAbout": m344,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "studioVersion": m345,
    "suggestPick": MessageLookupByLibrary.simpleMessage("Вибрати значення"),
    "sysActiveNote": MessageLookupByLibrary.simpleMessage(
      "Обслуговує лінки, потоки, шлюз і сусідів. Відповідає на `sys/replication/**` для свого резерву.",
    ),
    "sysAdminOnly": MessageLookupByLibrary.simpleMessage("sys/**, лише admin"),
    "sysArbiterLease": MessageLookupByLibrary.simpleMessage("Оренда арбітра"),
    "sysAround": MessageLookupByLibrary.simpleMessage("Близько (UTC)"),
    "sysAroundBad": MessageLookupByLibrary.simpleMessage(
      "Введіть час як гг:хх або гг:хх:сс.",
    ),
    "sysAroundClear": MessageLookupByLibrary.simpleMessage("Показати весь час"),
    "sysAroundHint": MessageLookupByLibrary.simpleMessage("гг:хх:сс"),
    "sysAttnAcl": m346,
    "sysAttnAclDetail": m347,
    "sysAttnBehind": m348,
    "sysAttnBehindDetail": m349,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag більший за 0: перемикання зараз втратить записи",
    ),
    "sysAttnBroker": m350,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage("Нижчий брокер"),
    "sysAttnBrokerRelays": m351,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysAttnLinkDetail": m352,
    "sysAttnLinkFailed": m353,
    "sysAttnNoStandby": MessageLookupByLibrary.simpleMessage(
      "За цим брокером не слідує резерв",
    ),
    "sysAttnNoStandbyDetail": MessageLookupByLibrary.simpleMessage(
      "standby_connected дорівнює 0",
    ),
    "sysAttnOpenAudit": MessageLookupByLibrary.simpleMessage(
      "Відкрити Аудит ›",
    ),
    "sysAttnOpenAvail": MessageLookupByLibrary.simpleMessage(
      "Відкрити Доступність ›",
    ),
    "sysAttnOpenLinks": MessageLookupByLibrary.simpleMessage(
      "Відкрити в Лінках ›",
    ),
    "sysAttnOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "Відкрити Карантин ›",
    ),
    "sysAttnOpenSites": MessageLookupByLibrary.simpleMessage(
      "Відкрити в Сайтах ›",
    ),
    "sysAttnQuarantine": m354,
    "sysAttnQuarantineDetail": m355,
    "sysAttnQuarantineSince": m356,
    "sysBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія та відновлення",
    ),
    "sysBackupNote": m357,
    "sysBackupNoteNoSize": MessageLookupByLibrary.simpleMessage(
      "Усе, чим володіє брокер, лежить у його `data_dir`. Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:",
    ),
    "sysBackupWarning": MessageLookupByLibrary.simpleMessage(
      "Резервна копія містить CA сайту і ключ шлюзу: хто її читає, той адміністратор. Зашифруйте її і тримайте там, де читати можуть лише адміністратори брокера.",
    ),
    "sysBannerBehind": MessageLookupByLibrary.simpleMessage("Резерв відстає"),
    "sysBannerBoth": MessageLookupByLibrary.simpleMessage(
      "Резерв відстає і відклав розгалуження",
    ),
    "sysBannerFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysBannerForks": m358,
    "sysBannerLag": m359,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("брокер (усе)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Рівень журналу брокера",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Байти"),
    "sysClear": m360,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Очистити ці від’єднані лінки?",
    ),
    "sysClearAskBody": m361,
    "sysClearBoard": m362,
    "sysClearConfirm": MessageLookupByLibrary.simpleMessage("Очистити"),
    "sysClearFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/clear_conns` · config · питає перед запуском",
    ),
    "sysClearNone": MessageLookupByLibrary.simpleMessage(
      "Очистити від’єднані лінки…",
    ),
    "sysClearOne": MessageLookupByLibrary.simpleMessage(
      "Очистити 1 від’єднаний лінк…",
    ),
    "sysCleared": m363,
    "sysClearedNone": MessageLookupByLibrary.simpleMessage(
      "Брокер не вилучив жодного лінка.",
    ),
    "sysCmdBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія (брокер зупинено)",
    ),
    "sysCmdBackupNote": MessageLookupByLibrary.simpleMessage(
      "Узгоджено й найпростіше. Зі знімком файлової системи (LVM, btrfs, ZFS) брокер може працювати далі.",
    ),
    "sysCmdCheck": MessageLookupByLibrary.simpleMessage(
      "Перед перезапуском зі зміненим файлом",
    ),
    "sysCmdCheckNote": MessageLookupByLibrary.simpleMessage(
      "Конфігурація розбирається і проходить перевірку; інакше код виходу 1.",
    ),
    "sysCmdVerify": MessageLookupByLibrary.simpleMessage("Перевірити копію"),
    "sysCmdVerifyNote": MessageLookupByLibrary.simpleMessage(
      "Перевіряє кожне сховище площини керування без запуску: CRC, ланцюг HMAC, якорі. Запустіть на відновленому data_dir перед стартом.",
    ),
    "sysCollecting": MessageLookupByLibrary.simpleMessage("Збираю…"),
    "sysCommandCopied": MessageLookupByLibrary.simpleMessage(
      "Команди скопійовано",
    ),
    "sysCopy": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "sysCopyCommand": m364,
    "sysDownstream": MessageLookupByLibrary.simpleMessage("Нижчі брокери"),
    "sysElsewhere": MessageLookupByLibrary.simpleMessage(
      "Також налаштування брокера, що лежать там, де їх застосовують:",
    ),
    "sysElsewhereAccess": MessageLookupByLibrary.simpleMessage(
      "Ролі та права › Доступ",
    ),
    "sysElsewhereHistory": MessageLookupByLibrary.simpleMessage(
      "Зберігання та очищення › Історія",
    ),
    "sysElsewhereLinks": MessageLookupByLibrary.simpleMessage(
      "Допуск нових лінків › Лінки › Карантин",
    ),
    "sysElsewhereSites": MessageLookupByLibrary.simpleMessage(
      "Токени для нижчих сайтів › Сайти",
    ),
    "sysEvery5s": MessageLookupByLibrary.simpleMessage("кожні 5 с"),
    "sysFactLiveliness": MessageLookupByLibrary.simpleMessage("Живучість"),
    "sysFactSite": MessageLookupByLibrary.simpleMessage("Сайт"),
    "sysFilter": MessageLookupByLibrary.simpleMessage("Фільтр"),
    "sysFilterHint": MessageLookupByLibrary.simpleMessage(
      "текст у джерелі або повідомленні",
    ),
    "sysFlow": MessageLookupByLibrary.simpleMessage(
      "WAL, файли, сховище, історія",
    ),
    "sysForks": MessageLookupByLibrary.simpleMessage("Відкладені розгалуження"),
    "sysFrames": MessageLookupByLibrary.simpleMessage("Кадри"),
    "sysGetLog": MessageLookupByLibrary.simpleMessage("Отримати журнал"),
    "sysGroupLinks": MessageLookupByLibrary.simpleMessage("Лінки та сайти"),
    "sysGroupProcess": MessageLookupByLibrary.simpleMessage("Процес і диск"),
    "sysGuideCopied": m365,
    "sysGuideLink": MessageLookupByLibrary.simpleMessage(
      "Посібник: docs/operations.md › Warm standby ›",
    ),
    "sysHeld": MessageLookupByLibrary.simpleMessage("Що зберігає резерв"),
    "sysHeldControl": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "sysHeldControlNote": MessageLookupByLibrary.simpleMessage(
      "Реєстр, визначення потоків і користувачі шлюзу: самі записи WAL, перевірені ланцюгом HMAC.",
    ),
    "sysHeldHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "sysHeldHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Рядки кожної серії з журналу змін, записані у власні денні файли резерву.",
    ),
    "sysHeldSecrets": MessageLookupByLibrary.simpleMessage(
      "Секрети та дані лінків",
    ),
    "sysHeldSecretsNote": MessageLookupByLibrary.simpleMessage(
      "secrets.bin, токени лінків, data_dir лінків і пакети: запечатані частини по 1 MiB, файли до 64 MiB, вилучені, коли зникли тут.",
    ),
    "sysHeldStorage": MessageLookupByLibrary.simpleMessage("Сховище брокера"),
    "sysHeldStorageNote": MessageLookupByLibrary.simpleMessage(
      "Журнал змін сховища, застосований до власного сховища резерву (ціле дерево понад 20 000 змін).",
    ),
    "sysIn": MessageLookupByLibrary.simpleMessage("вхід"),
    "sysLag": MessageLookupByLibrary.simpleMessage("Відставання"),
    "sysLevelMore": MessageLookupByLibrary.simpleMessage("Рівень і суворіші"),
    "sysLines": MessageLookupByLibrary.simpleMessage("Рядків"),
    "sysLinkSource": m366,
    "sysLogCopied": m367,
    "sysLogInvalid": m368,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Потрапляє до «Переглянути й застосувати»; після застосування діє одразу, без перезапуску, і замінює `RUST_LOG`. Zenoh лишається на warn нижче trace. Значення й токени не журналюються нижче trace. Власний рівень лінка: Лінки › лінк › Журнал.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Журнал читають із рівнем config на sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Не вдалося зберегти журнал",
    ),
    "sysLogSaved": m369,
    "sysLogSummary": m370,
    "sysLogSummaryAround": m371,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "sysMetaStarted": m372,
    "sysNeedsLook": m373,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "Зі значень самого брокера. Кожна картка відкриває екран, де це виправляють.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "На цьому рівні рядків немає.",
    ),
    "sysNoLinesAround": m374,
    "sysNoProfiles": MessageLookupByLibrary.simpleMessage("Профілів немає."),
    "sysNoStale": MessageLookupByLibrary.simpleMessage(
      "Від’єднаних лінків немає.",
    ),
    "sysNoStandbyBody": MessageLookupByLibrary.simpleMessage(
      "`sys/standby_connected` дорівнює 0. Теплий резерв не налаштовано, або налаштований не досягає цього брокера. Якщо цей хост відмовить, сайт зупиниться, доки хост не повернеться; лінки на інших машинах перейдуть до наступної адреси, лише якщо її мають.",
    ),
    "sysNoStandbyStep1": MessageLookupByLibrary.simpleMessage(
      "1. Скопіюйте ключі на другий хост: `wyrmd keys export` тут, `wyrmd keys import` там.",
    ),
    "sysNoStandbyStep2": m375,
    "sysNoStandbyStep3": MessageLookupByLibrary.simpleMessage(
      "3. Запустіть другий хост; ця вкладка покаже його за секунду.",
    ),
    "sysNoStandbySteps": MessageLookupByLibrary.simpleMessage(
      "Щоб додати резерв (на хостах, не в Studio)",
    ),
    "sysNoStandbyTitle": MessageLookupByLibrary.simpleMessage(
      "За цим брокером не слідує жоден резерв",
    ),
    "sysNotConnected": MessageLookupByLibrary.simpleMessage("не з’єднано"),
    "sysNothing": MessageLookupByLibrary.simpleMessage(
      "Ніщо не потребує уваги.",
    ),
    "sysNothingToClear": MessageLookupByLibrary.simpleMessage(
      "Немає від’єднаних лінків для очищення",
    ),
    "sysNow": m376,
    "sysOfTotal": m377,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Відкрити запис аудиту ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("вихід"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Пакети"),
    "sysProfileFile": m378,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Назва"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m379,
    "sysProfileRemoved": m380,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Профілі пристроїв"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Моделі, які брокер віддає як `pub/<vendor>:<model>`: точки, одиниці та діапазони, що їх успадковують лінки й асистент.",
    ),
    "sysProfilesUnlisted": m381,
    "sysPulled": MessageLookupByLibrary.simpleMessage("забирає щосекунди"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Додати профіль"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Додати профіль…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("записів"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Вилучити"),
    "sysRemoveProfile": m382,
    "sysRemoveProfileAsk": m383,
    "sysRunningActive": MessageLookupByLibrary.simpleMessage(
      "Працює · активний",
    ),
    "sysSaveLog": MessageLookupByLibrary.simpleMessage("Зберегти як .log"),
    "sysSecondsLeft": MessageLookupByLibrary.simpleMessage("с лишилось"),
    "sysSinceStart": MessageLookupByLibrary.simpleMessage("від запуску"),
    "sysSource": MessageLookupByLibrary.simpleMessage("Джерело"),
    "sysStale": MessageLookupByLibrary.simpleMessage("Від’єднані лінки"),
    "sysStaleNote": MessageLookupByLibrary.simpleMessage(
      "Лінки, допущені під час роботи, що працюють на інших машинах і зараз не з’єднані. Очищення вилучає їх із реєстру; їхні id вибувають і більше не можуть бути використані.",
    ),
    "sysStaleRow": m384,
    "sysStandbyBehind": MessageLookupByLibrary.simpleMessage(
      "Резерв · відстає",
    ),
    "sysStandbyConnected": MessageLookupByLibrary.simpleMessage(
      "Резерв з’єднано",
    ),
    "sysStandbyFollowing": MessageLookupByLibrary.simpleMessage(
      "Резерв · слідує",
    ),
    "sysStandbyNote": MessageLookupByLibrary.simpleMessage(
      "Ті самі ключі, власний `data_dir`. Перебирає роботу, лише коли цей брокер не відповідає, а свідок йому ще відповідає.",
    ),
    "sysSubAcl": MessageLookupByLibrary.simpleMessage(
      "від запуску маршрутизатора · відкрити Аудит",
    ),
    "sysSubAudit": MessageLookupByLibrary.simpleMessage(
      "хто що зробив · відкрити Аудит",
    ),
    "sysSubCpu": MessageLookupByLibrary.simpleMessage("100 = одне ядро"),
    "sysSubData": m385,
    "sysSubDisk": MessageLookupByLibrary.simpleMessage(
      "на файловій системі data_dir",
    ),
    "sysSubFollows": MessageLookupByLibrary.simpleMessage(
      "слідує за цим брокером через з’єднання сусідів",
    ),
    "sysSubForks": MessageLookupByLibrary.simpleMessage(
      "після усуненого розколу · аудит standby_forked",
    ),
    "sysSubForksNone": MessageLookupByLibrary.simpleMessage(
      "жодного розколу від запуску брокера",
    ),
    "sysSubLag": MessageLookupByLibrary.simpleMessage(
      "ще не на резерві: перемикання зараз їх втратить",
    ),
    "sysSubLagNone": MessageLookupByLibrary.simpleMessage(
      "резерв має всі записи реєстру",
    ),
    "sysSubLease": MessageLookupByLibrary.simpleMessage(
      "поновлює арбітр оренди",
    ),
    "sysSubLeaseLate": MessageLookupByLibrary.simpleMessage(
      "поновлюється пізно: перевірте хост арбітра",
    ),
    "sysSubLinkFailed": m386,
    "sysSubMemory": MessageLookupByLibrary.simpleMessage("резидентна"),
    "sysSubNoArbiter": MessageLookupByLibrary.simpleMessage(
      "арбітра не налаштовано",
    ),
    "sysSubOpenHistory": MessageLookupByLibrary.simpleMessage(
      "відкрити Історію",
    ),
    "sysSubOpenLinks": MessageLookupByLibrary.simpleMessage("відкрити Лінки"),
    "sysSubOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "відкрити Карантин",
    ),
    "sysSubOpenSites": MessageLookupByLibrary.simpleMessage("відкрити Сайти"),
    "sysSubPackages": MessageLookupByLibrary.simpleMessage(
      "встановлені пакети лінків",
    ),
    "sysSubPeer": m387,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "мережеві сесії; користувачів шлюзу не враховано",
    ),
    "sysSubWaits": m388,
    "sysTabAvailability": MessageLookupByLibrary.simpleMessage("Доступність"),
    "sysTabLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "sysTabMaintenance": MessageLookupByLibrary.simpleMessage("Обслуговування"),
    "sysTabOverview": MessageLookupByLibrary.simpleMessage("Огляд"),
    "sysTabsLabel": MessageLookupByLibrary.simpleMessage("Розділи системи"),
    "sysThisActive": MessageLookupByLibrary.simpleMessage(
      "Цей брокер · активний",
    ),
    "sysThisBroker": MessageLookupByLibrary.simpleMessage("Цей брокер"),
    "sysTraffic": MessageLookupByLibrary.simpleMessage("Трафік маршрутизатора"),
    "sysTrafficDescribe": m389,
    "sysTrafficNote": MessageLookupByLibrary.simpleMessage(
      "Зібрано зі значень `sys`, поки Studio відкрито (брокер не зберігає їхньої історії). Лише мережеві сесії: вбудовані лінки та користувачі шлюзу працюють усередині процесу, їх не враховано.",
    ),
    "sysUnitConnected": MessageLookupByLibrary.simpleMessage("з’єднано"),
    "sysUnreachable": MessageLookupByLibrary.simpleMessage("Недосяжний"),
    "sysUpstream": MessageLookupByLibrary.simpleMessage("Вищі брокери"),
    "systemFooter": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 задає початковий стан; усе, що змінено тут, живе в журналі попереднього запису.",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Дії"),
    "tabAudit": MessageLookupByLibrary.simpleMessage("Аудит"),
    "tabContents": MessageLookupByLibrary.simpleMessage("Вміст"),
    "tabGrants": MessageLookupByLibrary.simpleMessage("Дозволи"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Точки"),
    "tabUsers": MessageLookupByLibrary.simpleMessage("Користувачі"),
    "tableAddColumn": MessageLookupByLibrary.simpleMessage("Додати стовпець"),
    "tableAddRow": MessageLookupByLibrary.simpleMessage("Додати рядок"),
    "tableFilter": MessageLookupByLibrary.simpleMessage("Фільтр рядків"),
    "tableFiltered": m390,
    "tableMore": MessageLookupByLibrary.simpleMessage("Ще"),
    "tableNoColumns": MessageLookupByLibrary.simpleMessage(
      "таблиця без стовпців",
    ),
    "tableNoColumnsEdit": MessageLookupByLibrary.simpleMessage(
      "Стовпців ще немає. Додай стовпець кнопкою «Додати стовпець».",
    ),
    "tableNoRows": MessageLookupByLibrary.simpleMessage("Немає рядків"),
    "tableRefusedBytes": MessageLookupByLibrary.simpleMessage(
      "Відмовлено: клітинки таблиці займають не більше 512 KiB.",
    ),
    "tableRefusedColumns": MessageLookupByLibrary.simpleMessage(
      "Відмовлено: таблиця містить не більше 128 стовпців.",
    ),
    "tableRefusedName": MessageLookupByLibrary.simpleMessage(
      "Відмовлено: назва стовпця має від 1 до 256 байтів.",
    ),
    "tableRefusedNameTaken": MessageLookupByLibrary.simpleMessage(
      "Відмовлено: у таблиці вже є стовпець з цією назвою.",
    ),
    "tableRefusedRows": MessageLookupByLibrary.simpleMessage(
      "Відмовлено: таблиця містить не більше 10 000 рядків.",
    ),
    "tableRemoveColumn": MessageLookupByLibrary.simpleMessage(
      "Видалити стовпець",
    ),
    "tableRemoveRow": MessageLookupByLibrary.simpleMessage("Видалити рядок"),
    "tableRenameColumn": MessageLookupByLibrary.simpleMessage(
      "Перейменувати стовпець",
    ),
    "tagActiveStandby": MessageLookupByLibrary.simpleMessage(
      "активний + резерв",
    ),
    "tagDownstreamOf": m391,
    "tagNeeds": m392,
    "tagNew": MessageLookupByLibrary.simpleMessage("новий"),
    "tagPlainHttp": MessageLookupByLibrary.simpleMessage("простий http"),
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "tagUsedBefore": MessageLookupByLibrary.simpleMessage("вже використано"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("чекає схвалення"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "чекає на твою відповідь",
    ),
    "taskBy": m393,
    "taskDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "taskFailed": MessageLookupByLibrary.simpleMessage(
      "не вдалося або зупинено",
    ),
    "taskFailedAt": m394,
    "taskListNote": m395,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("нічого не змінено"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("планує"),
    "taskReplaced": m396,
    "taskRunning": MessageLookupByLibrary.simpleMessage("виконує"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "thisNetwork": MessageLookupByLibrary.simpleMessage("цій мережі"),
    "timelineAudit": MessageLookupByLibrary.simpleMessage("З sys/audit"),
    "timelineAuditLine": m397,
    "timelineAuditNone": MessageLookupByLibrary.simpleMessage(
      "Немає змін цієї точки в останніх 500 записах sys/audit.",
    ),
    "timelineLabel": m398,
    "tlsCertificateOf": m399,
    "tlsNotTrusted": m400,
    "tlsPinned": m401,
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Закрити"),
    "toastHidesIn": m402,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Сповіщення"),
    "toastStays": m403,
    "toastStream": MessageLookupByLibrary.simpleMessage(
      "Studio відкриє потоки знову, коли він повернеться.",
    ),
    "todayUsed": m404,
    "tokenForBelow": MessageLookupByLibrary.simpleMessage(
      "Токен для сайту нижче",
    ),
    "tokenHours": MessageLookupByLibrary.simpleMessage("Дійсний годин"),
    "tokenNote": MessageLookupByLibrary.simpleMessage(
      "Один токен одразу допускає брокер. Показується один раз; задайте кількість використань і години.",
    ),
    "tokenUses": MessageLookupByLibrary.simpleMessage("Використань"),
    "treeAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "treeActionNote": MessageLookupByLibrary.simpleMessage(
      "блок, що запускає її, коли run when стає true; її аргументи — поля.",
    ),
    "treeActionNote2": MessageLookupByLibrary.simpleMessage(
      "блок, що її виконує: її параметри є полями, які заповнюють інші блоки, з тригером.",
    ),
    "treeDraft": MessageLookupByLibrary.simpleMessage("чернетка"),
    "treeEmpty": MessageLookupByLibrary.simpleMessage("Тут нічого немає."),
    "treeLoading": MessageLookupByLibrary.simpleMessage("Читаю дерево…"),
    "treeNoteLead": MessageLookupByLibrary.simpleMessage(
      "Дерево показує лише дані.",
    ),
    "treeNoteMiddle": MessageLookupByLibrary.simpleMessage("змінюється в"),
    "treeOf": m405,
    "treePoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "на блоці: додає її як поле. На полотні: новий блок цього вузла.",
    ),
    "treePointNote2": MessageLookupByLibrary.simpleMessage(
      "на полотні: блок, що її читає (записувана точка питає «Читати» чи «Писати»; Alt пише). На полі: прив\'язується до нього.",
    ),
    "trendAll": MessageLookupByLibrary.simpleMessage("усе"),
    "trendAllHidden": MessageLookupByLibrary.simpleMessage("Усі ряди сховано."),
    "trendAvg": m406,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "записано погану якість",
    ),
    "trendBucket": m407,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть A ще раз, щоб прибрати її",
    ),
    "trendDelta": m408,
    "trendDescribe": m409,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("До поточного часу"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Наведіть для значень · тягніть по графіку, щоб наблизити · клацніть, щоб поставити мітку A · тягніть або змінюйте вікно внизу · подвійне клацання скидає · ← → рухають вибрану ручку",
    ),
    "trendHoursMinutes": m410,
    "trendLocked": m411,
    "trendMarker": m412,
    "trendMinMax": m413,
    "trendMinutes": m414,
    "trendMonths": MessageLookupByLibrary.simpleMessage(
      "січ,лют,бер,кві,тра,чер,лип,сер,вер,жов,лис,гру",
    ),
    "trendMoveWindow": MessageLookupByLibrary.simpleMessage(
      "Тягніть, щоб посунути вікно",
    ),
    "trendNoData": MessageLookupByLibrary.simpleMessage("немає даних"),
    "trendNoDataRecorded": MessageLookupByLibrary.simpleMessage(
      "даних не записано",
    ),
    "trendNothing": MessageLookupByLibrary.simpleMessage(
      "У цьому діапазоні немає записаних значень.",
    ),
    "trendNow": MessageLookupByLibrary.simpleMessage("зараз"),
    "trendPoint": m415,
    "trendRaw": MessageLookupByLibrary.simpleMessage("сирі"),
    "trendRawAt": m416,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Скинути масштаб"),
    "trendSeconds": m417,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть, щоб поставити мітку A",
    ),
    "trendShowHide": m418,
    "trendStepDays": m419,
    "trendStepHours": m420,
    "trendStepMinutes": m421,
    "trendUncertain": MessageLookupByLibrary.simpleMessage(
      "uncertain · застарілі читання в цьому інтервалі",
    ),
    "trendWeekdays": MessageLookupByLibrary.simpleMessage(
      "Пн,Вт,Ср,Чт,Пт,Сб,Нд",
    ),
    "trendWindowEnd": MessageLookupByLibrary.simpleMessage("Кінець вікна"),
    "trendWindowStart": MessageLookupByLibrary.simpleMessage("Початок вікна"),
    "trustCode": MessageLookupByLibrary.simpleMessage("Код CA"),
    "trustMatches": m422,
    "trustRefusedChain": m423,
    "trustRefusedChanged": MessageLookupByLibrary.simpleMessage(
      "Gateway тепер надсилає інший CA, ніж показано. Нічому не довірено.",
    ),
    "trustRefusedMismatch": MessageLookupByLibrary.simpleMessage(
      "Код, який заявляє gateway, не є кодом його CA. Нічому не довірено.",
    ),
    "trustRefusedNoAnswer": MessageLookupByLibrary.simpleMessage(
      "Gateway не відповів удруге. Нічому не довірено.",
    ),
    "trustTitle": m424,
    "trustWhere": m425,
    "trustWhy": m426,
    "tryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "typeOrFind": MessageLookupByLibrary.simpleMessage(
      "Введіть адресу або знайдіть її в цій мережі.",
    ),
    "unbind": MessageLookupByLibrary.simpleMessage("Розв’язати"),
    "unitNumber": m427,
    "unlockAgoNow": MessageLookupByLibrary.simpleMessage("зараз"),
    "unlockAnother": MessageLookupByLibrary.simpleMessage(
      "Інший обліковий запис або шлюз",
    ),
    "unlockCancelTitle": m428,
    "unlockChangedFaces": m429,
    "unlockChangedFingers": m430,
    "unlockChangedTitle": m431,
    "unlockChecking": m432,
    "unlockConfirmPrompt": m433,
    "unlockDeviceComputer": MessageLookupByLibrary.simpleMessage(
      "цьому комп’ютері",
    ),
    "unlockDeviceIphone": MessageLookupByLibrary.simpleMessage("цьому iPhone"),
    "unlockDeviceMac": MessageLookupByLibrary.simpleMessage("цьому Mac"),
    "unlockDevicePc": MessageLookupByLibrary.simpleMessage("цьому ПК"),
    "unlockDevicePhone": MessageLookupByLibrary.simpleMessage("цьому телефоні"),
    "unlockDontAsk": MessageLookupByLibrary.simpleMessage(
      "Не питати на цьому комп’ютері",
    ),
    "unlockDueText": m434,
    "unlockDueTitle": m435,
    "unlockEnablePrompt": m436,
    "unlockFactEndsFaces": MessageLookupByLibrary.simpleMessage(
      "Він перестає діяти, коли тут змінюються обличчя, коли змінюється ваш пароль або коли адміністратор видаляє цей пристрій.",
    ),
    "unlockFactEndsFingers": MessageLookupByLibrary.simpleMessage(
      "Він перестає діяти, коли тут змінюються відбитки пальців, коли змінюється ваш пароль або коли адміністратор видаляє цей пристрій.",
    ),
    "unlockFactPassword": m437,
    "unlockFactSite": m438,
    "unlockFactStandby": m439,
    "unlockFactStore": m440,
    "unlockFallbackText": m441,
    "unlockKeyIn": m442,
    "unlockLastPassword": MessageLookupByLibrary.simpleMessage("пароль"),
    "unlockLastUsed": m443,
    "unlockLockoutTitle": m444,
    "unlockLogInTo": m445,
    "unlockNameBiometric": MessageLookupByLibrary.simpleMessage("біометрію"),
    "unlockNameFace": MessageLookupByLibrary.simpleMessage(
      "розпізнавання обличчя",
    ),
    "unlockNameFingerprint": MessageLookupByLibrary.simpleMessage(
      "відбиток пальця",
    ),
    "unlockNameIris": MessageLookupByLibrary.simpleMessage("райдужку"),
    "unlockNoBioFactOther": MessageLookupByLibrary.simpleMessage(
      "На комп’ютері зі сканером відбитків відмикайте ним у macOS або Windows.",
    ),
    "unlockNoBioFactRemember": MessageLookupByLibrary.simpleMessage(
      "Studio пам’ятає шлюз і користувача, ніколи — пароль.",
    ),
    "unlockNoBioText": MessageLookupByLibrary.simpleMessage(
      "Studio може прив’язати ключ лише до Touch ID, Face ID, Windows Hello або відбитка на Android. Тут він щоразу питатиме пароль.",
    ),
    "unlockNoBioTitle": MessageLookupByLibrary.simpleMessage(
      "Цей комп’ютер не має біометричного відмикання",
    ),
    "unlockNoneLinux": MessageLookupByLibrary.simpleMessage(
      "У Linux немає системного запиту, до якого Studio може прив’язати ключ, тож цей комп’ютер завжди питає пароль.",
    ),
    "unlockNoneOther": MessageLookupByLibrary.simpleMessage(
      "Studio не знайшов тут налаштованого Touch ID чи Windows Hello, тож цей комп’ютер питає пароль.",
    ),
    "unlockNoneTitle": MessageLookupByLibrary.simpleMessage(
      "На цьому комп’ютері немає біометричного відмикання",
    ),
    "unlockNotNow": MessageLookupByLibrary.simpleMessage("Не зараз"),
    "unlockOffText": MessageLookupByLibrary.simpleMessage(
      "Адміністратор вимкнув пристрої на цьому шлюзі. Studio видалив свій ключ; увійдіть з паролем.",
    ),
    "unlockOffTitle": m446,
    "unlockOffToast": m447,
    "unlockOfferChecked": m448,
    "unlockOfferText": m449,
    "unlockOfferTitle": m450,
    "unlockOpenStudio": MessageLookupByLibrary.simpleMessage("Відкрити Studio"),
    "unlockOrEnter": MessageLookupByLibrary.simpleMessage(
      "Або натисніть Enter",
    ),
    "unlockPasswordChangedText": MessageLookupByLibrary.simpleMessage(
      "Новий пароль виводить з усіх пристроїв. Увійдіть з новим.",
    ),
    "unlockPasswordChangedTitle": MessageLookupByLibrary.simpleMessage(
      "Ваш пароль змінився",
    ),
    "unlockPasswordFor": m451,
    "unlockPlusStandby": m452,
    "unlockPolicyLine": m453,
    "unlockPrompt": m454,
    "unlockReEnable": m455,
    "unlockRemovedText": m456,
    "unlockRemovedTitle": MessageLookupByLibrary.simpleMessage(
      "Видалено адміністратором",
    ),
    "unlockRoleOn": m457,
    "unlockStoreAndroid": MessageLookupByLibrary.simpleMessage(
      "апаратному сховищі ключів цього телефона",
    ),
    "unlockStoreIos": MessageLookupByLibrary.simpleMessage(
      "Secure Enclave цього iPhone",
    ),
    "unlockStoreMac": MessageLookupByLibrary.simpleMessage(
      "Secure Enclave цього Mac",
    ),
    "unlockStoreWindows": MessageLookupByLibrary.simpleMessage("TPM цього ПК"),
    "unlockToOpen": m458,
    "unlockUnknownText": m459,
    "unlockUnknownTitle": m460,
    "unlockUse": m461,
    "unlockUsePassword": MessageLookupByLibrary.simpleMessage(
      "Увійти з паролем",
    ),
    "unlockWelcomeBack": MessageLookupByLibrary.simpleMessage("З поверненням"),
    "unlockWith": m462,
    "unpinField": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "Брокер, можливо, перезапускається, або цей комп’ютер в іншій мережі.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "Точка більше не записується; рядки лишаються.",
    ),
    "upFor": m463,
    "updAllOfficial": MessageLookupByLibrary.simpleMessage(
      "Оновити всі офіційні…",
    ),
    "updAsksMore": MessageLookupByLibrary.simpleMessage(
      "Він просить більше прав",
    ),
    "updAuditRollback": MessageLookupByLibrary.simpleMessage(
      "Аудит: update_rollback",
    ),
    "updAuditUpdate": MessageLookupByLibrary.simpleMessage(
      "Аудит: package_update, restore_point",
    ),
    "updBefore": MessageLookupByLibrary.simpleMessage("Перед початком"),
    "updChecking": MessageLookupByLibrary.simpleMessage("перевірка стану"),
    "updChooseArchive": MessageLookupByLibrary.simpleMessage("Вибрати архів…"),
    "updClose": MessageLookupByLibrary.simpleMessage("Закрити"),
    "updColPackage": MessageLookupByLibrary.simpleMessage("Пакет"),
    "updColVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "updCustom": MessageLookupByLibrary.simpleMessage("власний"),
    "updDo": m464,
    "updFailed": m465,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "Перевірка стану закінчилась без відповіді від кожного лінка.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("Новіший архів"),
    "updFromFileNote": m466,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Оновити з файлу…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("зникли"),
    "updHotStart": m467,
    "updHotStartNote": MessageLookupByLibrary.simpleMessage(
      "Запущений застосунок отримує новий код на місці.",
    ),
    "updKept": MessageLookupByLibrary.simpleMessage(
      "Налаштування і вузли зберігаються",
    ),
    "updKeptNote": MessageLookupByLibrary.simpleMessage(
      "Кожен лінк зберігає свої приватні дані; нова версія їх читає.",
    ),
    "updKeptTile": MessageLookupByLibrary.simpleMessage("збережено"),
    "updKeptUntil": m468,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "Можна піти з цього екрана; оновлення триває.",
    ),
    "updLinksCount": m469,
    "updLinksRestart": m470,
    "updLinksRestartNote": MessageLookupByLibrary.simpleMessage(
      "Їхні значення зупиняються на час перезапуску; вузли оголошуються знову з налаштувань, які вони зберігають.",
    ),
    "updNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Потрібен config на sys/links",
    ),
    "updNeverUpdated": MessageLookupByLibrary.simpleMessage(
      "Цей пакет ще не оновлювали на цьому брокері.",
    ),
    "updNewTile": MessageLookupByLibrary.simpleMessage("нові"),
    "updNoNotes": MessageLookupByLibrary.simpleMessage(
      "Репозиторій не дає приміток до цієї версії.",
    ),
    "updNoPoints": MessageLookupByLibrary.simpleMessage(
      "Для його лінків немає збережених точок відновлення.",
    ),
    "updNodes": MessageLookupByLibrary.simpleMessage("Вузли до і після"),
    "updNothing": MessageLookupByLibrary.simpleMessage("Усі пакети актуальні."),
    "updOfficial": MessageLookupByLibrary.simpleMessage("офіційний"),
    "updOpenLink": m471,
    "updOpenLog": MessageLookupByLibrary.simpleMessage("Відкрити журнал"),
    "updOptAccept": MessageLookupByLibrary.simpleMessage(
      "Прийняти нові права, які він просить",
    ),
    "updOptAuto": MessageLookupByLibrary.simpleMessage(
      "Відкотити самостійно, якщо лінк не повернеться з усіма вузлами за 2 хв",
    ),
    "updOptPoint": MessageLookupByLibrary.simpleMessage(
      "Зберегти точку відновлення кожного лінка (налаштування, секрети, приватні дані)",
    ),
    "updOptPointLocked": MessageLookupByLibrary.simpleMessage(
      "Формат сховища змінюється: відкату потрібна точка відновлення",
    ),
    "updPillDone": MessageLookupByLibrary.simpleMessage("готово"),
    "updPillFailed": MessageLookupByLibrary.simpleMessage("помилка"),
    "updPillRolledBack": MessageLookupByLibrary.simpleMessage("відкочено"),
    "updPillUnknown": MessageLookupByLibrary.simpleMessage("невідомо"),
    "updPointBeforeRestore": m472,
    "updPointBeforeUpdate": m473,
    "updPoints": MessageLookupByLibrary.simpleMessage("Точки відновлення"),
    "updRights": MessageLookupByLibrary.simpleMessage("Права і мережа"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "Якщо нова версія просить більше, ніж мають лінки, брокер нічого не встановлює і показує перелік тут для прийняття.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Відкотити"),
    "updRollBackNote": m474,
    "updRollBackTitle": m475,
    "updRollBackTo": m476,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "Лінки знову працюють на збереженій версії.",
    ),
    "updRolledBackTo": m477,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("перевіряється"),
    "updRuns": m478,
    "updRunsNote": m479,
    "updStateChanges": m480,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "Стара версія не читає нове сховище: відкат відновлює сховище з точки відновлення.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Формат сховища: каже архів",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "Якщо архів не читає встановлений формат сховища, брокер відмовляє в оновленні без точки відновлення.",
    ),
    "updStateSame": m481,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "Нова версія читає сховище встановленої.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Стан: кожен лінк повернувся зі своїми вузлами",
    ),
    "updStepNodesCount": m482,
    "updStepPackage": MessageLookupByLibrary.simpleMessage(
      "Пакет отримано, перевірено і розпаковано поруч зі старою версією",
    ),
    "updStepPoint": MessageLookupByLibrary.simpleMessage(
      "Точки відновлення збережено",
    ),
    "updStepPointSaved": MessageLookupByLibrary.simpleMessage(
      "по одній на лінк",
    ),
    "updStepRestart": MessageLookupByLibrary.simpleMessage(
      "Лінки перезапущено",
    ),
    "updStopAndRollBack": MessageLookupByLibrary.simpleMessage(
      "Зупинити і відкотити",
    ),
    "updSubCustom": m483,
    "updSubOfficial": m484,
    "updTab": MessageLookupByLibrary.simpleMessage("Оновлення"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Лінки, пакет яких має новішу версію. Усі лінки пакета оновлюються разом, і брокер зберігає потрібне для повернення.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Потім"),
    "updTitle": m485,
    "updTitleCustom": m486,
    "updTitleDone": m487,
    "updTitleRolledBack": m488,
    "updTogether": MessageLookupByLibrary.simpleMessage("оновлюються разом"),
    "updUnknownResult": m489,
    "updUnknownResultNote": MessageLookupByLibrary.simpleMessage(
      "Studio не знає такого результату. Більше скаже журнал брокера.",
    ),
    "updUpdating": m490,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Оновлення…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Значення його лінків зупиняються на час перезапуску.",
    ),
    "updVersionsOf": m491,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "Що змінюється для брокера",
    ),
    "updWhatIsNew": m492,
    "updWorking": MessageLookupByLibrary.simpleMessage("встановлення"),
    "updating": MessageLookupByLibrary.simpleMessage("Оновлення…"),
    "upstream": MessageLookupByLibrary.simpleMessage("вище"),
    "upstreamBroker": MessageLookupByLibrary.simpleMessage("Верхній брокер"),
    "upstreamFooter": MessageLookupByLibrary.simpleMessage(
      "Верхній із wyrmd.json5 змінюють там; доданий тут видаляють через sys/upstream/<name> ▸ Remove.",
    ),
    "useStandby": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "user": MessageLookupByLibrary.simpleMessage("Користувач"),
    "userActive": MessageLookupByLibrary.simpleMessage("Активний"),
    "userDisabled": MessageLookupByLibrary.simpleMessage("Вимкнено"),
    "validate": MessageLookupByLibrary.simpleMessage("Перевірити"),
    "valueCopied": MessageLookupByLibrary.simpleMessage("Значення скопійовано"),
    "valuesDeployed": MessageLookupByLibrary.simpleMessage("розгорнута версія"),
    "valuesPreview": MessageLookupByLibrary.simpleMessage(
      "перегляд чернетки; нічого не записано",
    ),
    "versionDeployed": m493,
    "viaSite": m494,
    "viewValue": MessageLookupByLibrary.simpleMessage("Переглянути значення"),
    "viewerBadBool": MessageLookupByLibrary.simpleMessage("true або false"),
    "viewerBadJson": MessageLookupByLibrary.simpleMessage(
      "Не JSON-об’єкт і не список",
    ),
    "viewerBadNumber": MessageLookupByLibrary.simpleMessage("Не число"),
    "viewerCopyCsv": MessageLookupByLibrary.simpleMessage("Копіювати CSV"),
    "viewerCopyJson": MessageLookupByLibrary.simpleMessage("Копіювати JSON"),
    "viewerCsvHeaderOff": MessageLookupByLibrary.simpleMessage(
      "без рядка назв",
    ),
    "viewerCsvHeaderOn": MessageLookupByLibrary.simpleMessage(
      "перший рядок містить назви стовпців",
    ),
    "viewerCsvRefused": MessageLookupByLibrary.simpleMessage(
      "Блок відмовляє цьому тексту (parse_error): у ньому немає рядка, або він перевищує межу таблиці.",
    ),
    "viewerCsvRules": m495,
    "viewerCsvWired": MessageLookupByLibrary.simpleMessage(
      "Роздільник або заголовок надходить дротом: таблиця бере їхні поточні значення.",
    ),
    "viewerDiscard": MessageLookupByLibrary.simpleMessage("Відкинути"),
    "viewerEdit": MessageLookupByLibrary.simpleMessage("Редагувати"),
    "viewerEditJson": MessageLookupByLibrary.simpleMessage(
      "Редагувати як JSON",
    ),
    "viewerEmpty": MessageLookupByLibrary.simpleMessage(
      "Порожньо: поле повернеться до типового значення",
    ),
    "viewerLockedBound": MessageLookupByLibrary.simpleMessage(
      "Лише читання: поле живить зв’язок. Розв’яжіть його, щоб ввести значення.",
    ),
    "viewerLockedInput": MessageLookupByLibrary.simpleMessage(
      "Лише читання: цей вхід не має введеного значення. Зв’яжіть з ним вихід.",
    ),
    "viewerLockedOutput": MessageLookupByLibrary.simpleMessage(
      "Лише читання: цей вихід обчислює блок.",
    ),
    "viewerSave": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "viewerSaveHint": m496,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("Як таблиця"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Текст"),
    "viewerTableHint": m497,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "waitingToBeLetIn": m498,
    "wasValue": m499,
    "wasWord": MessageLookupByLibrary.simpleMessage("було"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Група спостереження"),
    "watchGroups": m500,
    "waysCaution": m501,
    "waysNote": MessageLookupByLibrary.simpleMessage(
      "Вибір — це нове прохання. Його план перевіряють, і він чекає на ваше схвалення крок за кроком.",
    ),
    "waysOut": MessageLookupByLibrary.simpleMessage("Що далі"),
    "welcomeUser": m502,
    "whatItRead": MessageLookupByLibrary.simpleMessage("Що прочитано"),
    "whyAnnounce": MessageLookupByLibrary.simpleMessage(
      "На брокері може бути вимкнено gateway.announce (захищені сайти), або його gateway слухає лише loopback.",
    ),
    "whyBring": MessageLookupByLibrary.simpleMessage(
      "Приносьте власний пакет лише тоді, коли його немає в офіційному списку. Zip, URL або Git-репозиторій зі зібраним пакетом, або один компонент.",
    ),
    "whyBringBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія лінка — це один файл з усім потрібним для його повернення. Studio читає тут її маніфест; брокер перевіряє все як новий лінк.",
    ),
    "whyBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "whyCheck": MessageLookupByLibrary.simpleMessage(
      "Перед встановленням перевіряються архів і вміст: розмір, шляхи, маніфест і його поля, версія протоколу, для яких хостів є бінарники.",
    ),
    "whyChoose": MessageLookupByLibrary.simpleMessage(
      "Більшість лінків — з офіційного списку: драйвер у wyrmd або пакет із вашого репозиторію. Власний пакет — лише якщо його там немає.",
    ),
    "whyDeauthorized": MessageLookupByLibrary.simpleMessage("Відкликано"),
    "whyFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер відповів success: false. Його повідомлення пояснює чому.",
    ),
    "whyInstalled": MessageLookupByLibrary.simpleMessage(
      "Він працює, має власну ідентичність і оголосив свою гілку.",
    ),
    "whyInstalling": MessageLookupByLibrary.simpleMessage(
      "Це триває кілька секунд. Можна піти — встановлення продовжиться.",
    ),
    "whyMulticast": MessageLookupByLibrary.simpleMessage(
      "Multicast не проходить через цю мережу: гостьовий Wi-Fi, VPN або VLAN без відбивача mDNS.",
    ),
    "whyNew": MessageLookupByLibrary.simpleMessage("Новий"),
    "whyPermission": MessageLookupByLibrary.simpleMessage(
      "Studio, можливо, не має дозволу бачити локальну мережу.",
    ),
    "whyPermissionIos": MessageLookupByLibrary.simpleMessage(
      "Studio, можливо, не має дозволу бачити локальну мережу. iOS: Параметри › Приватність і безпека › Локальна мережа.",
    ),
    "whyPermissionMac": MessageLookupByLibrary.simpleMessage(
      "Studio, можливо, не має дозволу бачити локальну мережу. macOS: Системні параметри › Приватність і безпека › Локальна мережа.",
    ),
    "whyRunBackup": MessageLookupByLibrary.simpleMessage(
      "Залиште його ідентифікатор, щоб відновити, або дайте новий, щоб створити другий лінк. Режим той, у якому він працював.",
    ),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер. Лише брокери, для чийого хоста зібрано пакет, можуть його прийняти; спосіб роботи задає тип пакета.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер, потім як лінк на ньому працюватиме. Вбудований драйвер може працювати в брокері, окремим процесом або на іншій машині.",
    ),
    "whyType": MessageLookupByLibrary.simpleMessage(
      "Ви завжди можете ввести адресу або відкрити посилання чи код зі сторінки System брокера.",
    ),
    "windowClose": MessageLookupByLibrary.simpleMessage("Закрити вікно"),
    "windowMaximize": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "windowMinimize": MessageLookupByLibrary.simpleMessage("Згорнути"),
    "windowRestore": MessageLookupByLibrary.simpleMessage("Відновити"),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Задається типом даних: суфіксом _wswap, _bswap або _wbswap.",
    ),
    "wouldRun": m503,
    "wouldSend": m504,
    "wouldWrite": m505,
    "writableNeeds": m506,
    "wrongPassword": MessageLookupByLibrary.simpleMessage(
      "Неправильний користувач або пароль. Попросіть адміністратора скинути пароль; gateway ніколи не надсилає його поштою.",
    ),
    "wsAccess": MessageLookupByLibrary.simpleMessage("Доступ"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Асистент"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Дерево"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Потоки"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Сайти"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("Система"),
    "wyrmdOn": m507,
    "yes": MessageLookupByLibrary.simpleMessage("так"),
    "youTag": MessageLookupByLibrary.simpleMessage("ВИ"),
    "yourAnswers": MessageLookupByLibrary.simpleMessage("Ваші відповіді"),
    "yourAnswersNote": MessageLookupByLibrary.simpleMessage(
      "Ваші відповіді. Натисніть крок ліворуч, щоб змінити.",
    ),
    "yourUpstream": MessageLookupByLibrary.simpleMessage("ваш верхній"),
    "zipFile": MessageLookupByLibrary.simpleMessage("Zip-файл"),
  };
}
