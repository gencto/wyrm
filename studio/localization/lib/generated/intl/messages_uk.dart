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

  static String m7(id) => "невідомо: потрібен config на sys/links/${id}";

  static String m8(count) =>
      "${Intl.plural(count, one: 'Застосувати 1 зміну', few: 'Застосувати ${count} зміни', other: 'Застосувати ${count} змін')}";

  static String m9(n) =>
      "${Intl.plural(n, one: '1 крок без позначки змінює щось і виконується власним ключем агента; його не можна пропустити. Щоб зупинити його, відхиліть план.', few: '${n} кроки без позначки змінюють щось і виконуються власним ключем агента; їх не можна пропустити. Щоб зупинити їх, відхиліть план.', other: '${n} кроків без позначки змінюють щось і виконуються власним ключем агента; їх не можна пропустити. Щоб зупинити їх, відхиліть план.')}";

  static String m10(n) =>
      "${Intl.plural(n, one: 'Схвалити 1 зміну й запустити', few: 'Схвалити ${n} зміни й запустити', other: 'Схвалити ${n} змін і запустити')}";

  static String m11(site) =>
      "Це завдання на сайті ${site}. Цей шлюз підписує схвалення лише для завдань власного сайту. Схваліть його через шлюз сайту ${site}.";

  static String m12(why) => "Схвалення відхилено; завдання ще чекає. ${why}";

  static String m13(n) =>
      "Спершу покажіть аргументи кроку ${n}: його схема невідома, тому їх приховано.";

  static String m14(role) =>
      "Підписує один токен на кожен позначений крок з вашими правами (${role}). Непозначені кроки пропускаються.";

  static String m15(count) => "Попросити адміністратора: ${count}";

  static String m16(n) => "просить приєднатися · ретранслює ${n}";

  static String m17(sites) => "просить ретранслювати: ${sites}";

  static String m18(code) => "відмовлено (${code})";

  static String m19(id) =>
      "Лінк ${id} уже є на цьому брокері: його буде замінено на місці (той самий драйвер і режим), спершу створюється його точка відновлення.";

  static String m20(size, rights) => "Близько ${size} · ${rights}";

  static String m21(days) =>
      "Створюються під час роботи брокера і зберігаються на ньому ${days} днів. Завантажте копію або надішліть у файлове сховище.";

  static String m22(name) => "Виберіть теку для ${name}";

  static String m23(link) => "Створити копію ${link}";

  static String m24(when) =>
      "Зберігається на брокері до ${when} (резервні копії).";

  static String m25(done, size) => "Завантаження: ${done} з ${size}";

  static String m26(what) => "Копію ${what} не створено";

  static String m27(site) =>
      "У ній ключі сайту: хто має файл і парольну фразу, той адміністратор ${site}.";

  static String m28(link) => "лінк ${link}";

  static String m29(n) => "Щонайменше ${n} символів";

  static String m30(what) => "Створення копії ${what}";

  static String m31(name) => "Видалити ${name}?";

  static String m32(percent) => "створюється · ${percent} %";

  static String m33(percent) => "надсилається · ${percent} %";

  static String m34(name) => "Збережено ${name}";

  static String m35(size, n) => "${size} · секцій: ${n}";

  static String m36(path) => "Збережено до ${path}; SHA-256 перевірено.";

  static String m37(site) =>
      "запечатано для ${site}: відкривається лише на брокері з його ключами";

  static String m38(error) => "Не надіслано: ${error}";

  static String m39(to) => "Надсилання до ${to}";

  static String m40(link) =>
      "Один файл .wyrm-link з усім, що потрібно ${link} для повернення тут або на іншому брокері.";

  static String m41(site) => "Резервна копія ${site}";

  static String m42(link) => "Резервна копія лінка ${link}";

  static String m43(days) => "Зберігається в резервних копіях ${days} днів.";

  static String m44(days) =>
      "Завантажується частинами, коли готова; також зберігається на брокері ${days} днів.";

  static String m45(n) =>
      "${Intl.plural(n, one: '${n} блок', few: '${n} блоки', other: '${n} блоків')}";

  static String m46(brokers, devices) =>
      "${brokers} брокерів · ${devices} пристроїв";

  static String m47(driver) => "вбудований драйвер ${driver}";

  static String m48(version) => "Знову на ${version}";

  static String m49(tried, version) =>
      "${tried} не пройшла пробний старт. Наступний старт повернув ${version} і відновив площину керування з копії перед оновленням.";

  static String m50(version, latest) => "${version} · доступна ${latest}";

  static String m51(version) => "${version} · актуальна";

  static String m52(version) => "${version} · оновлення відкочено";

  static String m53(version) => "${version} на випробуванні";

  static String m54(version) =>
      "Якщо нова версія записує новішу SCHEMA, ${version} потім її не прочитає: відкат відновлює копію площини керування, зроблену перед оновленням, тож зміни після оновлення втрачаються.";

  static String m55(from, to) => "Зупинено на ${from}, запущено на ${to}";

  static String m56(version) => "${version} підготовлено";

  static String m57(back, all, seconds) => "${back} з ${all} за ${seconds} с";

  static String m58(time) =>
      "Studio втратила шлюз і пробує знову самостійно · ${time}";

  static String m59(version) => "Відкрити журнал ${version}";

  static String m60(site, version) => "${site} перезапускається на ${version}";

  static String m61(site, version) => "Відкотити ${site} до ${version}?";

  static String m62(when) => "можливий до ${when}";

  static String m63(site, version) => "${site} працює на ${version}";

  static String m64(version) =>
      "Оновлення підтверджено; ${version} і копія перед оновленням зберігаються для відкату.";

  static String m65(n) => "${n} с";

  static String m66(version) =>
      "Новий бінарник розміщується поруч із поточним; ${version} залишається на диску.";

  static String m67(version) =>
      "Брокер чисто зупиняється, і менеджер служб запускає ${version} (приблизно 5–15 с без брокера).";

  static String m68(version) =>
      "${version} працює на випробуванні: за 3 хв мають повернутися роутер, шлюз і його лінки.";

  static String m69(version) =>
      "Потім він підтверджує себе. Якщо ні, наступний старт повертає ${version} з копією з кроку 1.";

  static String m70(site, version) => "Оновити ${site} до wyrmd ${version}";

  static String m71(site) => "Введіть ${site} для підтвердження";

  static String m72(site) => "${site} оновлено";

  static String m73(site) => "Оновлення ${site}";

  static String m74(site) => "підписано CA · ${site} CA";

  static String m75(n) =>
      "${Intl.plural(n, one: '1 блок стає', few: '${n} блоки стають', other: '${n} блоків стають')} одним блоком цього флоу. Дроти, що перетинають його межу, стають його входами та виходами.";

  static String m76(n) =>
      "${Intl.plural(n, zero: 'нічого · його здогад', one: '1 зміна · його здогад', few: '${n} зміни · його здогад', other: '${n} змін · його здогад')}";

  static String m77(count) =>
      "${Intl.plural(count, zero: 'без дочірніх вузлів', one: '${count} дочірній вузол', few: '${count} дочірні вузли', other: '${count} дочірніх вузлів')}";

  static String m78(entry) => "файлу ${entry} немає в zip";

  static String m79(n) => "записів: ${n}";

  static String m80(hosts) => "немає файлу для ${hosts}";

  static String m81(what) => "${what} завантажує брокер";

  static String m82(kib) => "${kib} KiB";

  static String m83(kib, files) => "${kib} KiB, файлів: ${files}";

  static String m84(id, mode, driver, site, broker, created) =>
      "${id} · ${mode} · ${driver} · із ${site} (wyrmd ${broker}, ${created})";

  static String m85(field) => "немає ${field}";

  static String m86(fields) => "немає або хибні: ${fields}";

  static String m87(name, version) =>
      "${name} ${version}: назва — сегмент ключа, версія — 1–32 знаки з A–Z a–z 0–9 . _ - +";

  static String m88(host) => "немає файлу для ${host}";

  static String m89(file) => "у корені архіву немає ${file}";

  static String m90(file) => "${file} — не JSON";

  static String m91(file, at) => "${file} — не JSON (на знаку ${at})";

  static String m92(file) => "${file} — не об’єкт JSON";

  static String m93(mib) =>
      "${mib} MiB: Studio не читає; брокер перевірить після вивантаження. Назви лінк на наступному кроці";

  static String m94(entry) => "${entry} — не WebAssembly";

  static String m95(kind) =>
      "копія виду ${kind}: «Додати лінк» бере копію лінка (.wyrm-link); копію брокера відновлюють у Системі";

  static String m96(name, version) => "${name} ${version}, є у файлі";

  static String m97(name, version) =>
      "${name} ${version} немає у файлі: він має бути встановлений на брокері";

  static String m98(path) => "шлях не відносний: ${path}";

  static String m99(n) => "wyrm_link ${n}";

  static String m100(found, speak) =>
      "wyrm_link ${found}; брокери працюють з ${speak}";

  static String m101(site) =>
      "запечатано для ${site}: файл відкриється лише на брокері з ключами цього сайту";

  static String m102(name) => "символьне посилання: ${name}";

  static String m103(file) =>
      "${file} має глибшу вкладеність, ніж дозволено маніфесту";

  static String m104(mib, limit) => "${mib} MiB; не більше ніж ${limit} MiB";

  static String m105(mib, limit) =>
      "${mib} MiB у zip; не більше ніж ${limit} MiB";

  static String m106(files, mib, maxFiles, maxMib) =>
      "файлів: ${files}, розпаковано ${mib} MiB; не більше ніж ${maxFiles} і ${maxMib} MiB";

  static String m107(field) => "${field} — поле, якого цей файл не має";

  static String m108(fields) => "невідомі поля: ${fields}";

  static String m109(field, found) =>
      "${field}: ${found} — назва, якої ця Studio не знає";

  static String m110(field) => "${field} має не ту форму, яку має в маніфесті";

  static String m111(answer) => "з картки: ${answer}";

  static String m112(answer) => "своїми словами: ${answer}";

  static String m113(site) =>
      "${site} під’єднується до нього; там авторизують ${site}.";

  static String m114(size) => "data_dir ${size}";

  static String m115(id) => "Відкликати допуск ${id}?";

  static String m116(flow) =>
      "Чернетка «${flow}» замінить версію, що працює зараз.";

  static String m117(who) => "розгорнув ${who}";

  static String m118(name) => "Забути ${name}?";

  static String m119(method, when) => "${method} · ${when}";

  static String m120(user) =>
      "${user} більше не зможе відмикати ним; лише вхід з паролем. Запис лишається як видалений вами, доки його не забудуть.";

  static String m121(name) => "Видалити ${name}?";

  static String m122(n, where) =>
      "${Intl.plural(n, one: '${n} gateway у ${where} · оголошено через DNS-SD', few: '${n} gateway у ${where} · оголошено через DNS-SD', other: '${n} gateway у ${where} · оголошено через DNS-SD')}";

  static String m123(where) => "Пошук у ${where}…";

  static String m124(where) => "За 8 с у ${where} не відповів жоден gateway";

  static String m125(n, range) =>
      "${Intl.plural(n, one: '${n} gateway у ${range} · знайдено перевіркою діапазону', few: '${n} gateway у ${range} · знайдено перевіркою діапазону', other: '${n} gateway у ${range} · знайдено перевіркою діапазону')}";

  static String m126(range, port) => "Перевірка ${range} на порту ${port}…";

  static String m127(steps) =>
      "Завдання виконано. Пропущені кроки: ${steps}. Попросіть їх окремим завданням; його план схвалюють окремо.";

  static String m128(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m129(id) => "Параметри ${id}";

  static String m130(time) =>
      "Решта подробиць у журналі брокера близько ${time}.";

  static String m131(field) =>
      "У формі поле ${field} позначено; виправте його та надішліть знову.";

  static String m132(role, site) =>
      "Ваша роль: ${role}. На ${site} нічого не змінено.";

  static String m133(call, key) => "${call} на ${key}";

  static String m134(type) => "studio · ${type}";

  static String m135(thing) => "розгорнути ${thing}";

  static String m136(thing) => "встановити ${thing}";

  static String m137(thing) => "отримати список ${thing}";

  static String m138(thing) => "увійти до ${thing}";

  static String m139(thing) => "відкрити ${thing}";

  static String m140(thing) => "прочитати ${thing}";

  static String m141(thing) => "вилучити ${thing}";

  static String m142(call, thing) => "виконати ${call} на ${thing}";

  static String m143(thing) => "зберегти ${thing}";

  static String m144(thing) => "запустити ${thing}";

  static String m145(step) => "завершити «${step}»";

  static String m146(thing) => "зупинити ${thing}";

  static String m147(thing) => "записати ${thing}";

  static String m148(thing) => "Розгортання ${thing}";

  static String m149(thing) => "Встановлення ${thing}";

  static String m150(thing) => "Список ${thing}";

  static String m151(thing) => "Вхід до ${thing}";

  static String m152(thing) => "Відкриття ${thing}";

  static String m153(thing) => "Читання ${thing}";

  static String m154(thing) => "Вилучення ${thing}";

  static String m155(call, thing) => "${call} на ${thing}";

  static String m156(thing) => "Збереження ${thing}";

  static String m157(thing) => "Запуск ${thing}";

  static String m158(thing) => "Зупинка ${thing}";

  static String m159(thing) => "Запис ${thing}";

  static String m160(why) => "${why}. Нічого не надіслано.";

  static String m161(call) => "${call}";

  static String m162(site) => "Брокер на ${site} не відповів.";

  static String m163(status) => "Брокер відповів ${status} без повідомлення.";

  static String m164(status, message) => "${status}: ${message}";

  static String m165(time) => "${time} (місцевий)";

  static String m166(doing, site) => "${doing}: помилка на ${site}";

  static String m167(doing) => "${doing}: помилка";

  static String m168(site, what) => "${site} зайнятий: ${what} не почато";

  static String m169(thing) => "${thing} більше немає";

  static String m170(thing) => "Історія ${thing} недоступна";

  static String m171(site) => "${site} не відповідає";

  static String m172(thing) => "Не вдалося прочитати ${thing}";

  static String m173(what) => "Ви не можете ${what}";

  static String m174(site) => "Живі значення з ${site} зупинилися";

  static String m175(what) => "Studio не вдалося ${what}";

  static String m176(thing, call) => "${thing} не підтримує ${call}";

  static String m177(seconds) => "Ще раз через ${seconds} с";

  static String m178(user, role) => "${user} (${role})";

  static String m179(s) => "кожні ${s} с";

  static String m180(version) => "v${version}";

  static String m181(reason) =>
      "Нечитаний файл не вдалося відкласти: ${reason}";

  static String m182(name) =>
      "Нечитаний файл лишиться поруч із новим як ${name}. Ви знову додасте свої gateway та увійдете.";

  static String m183(panel) => "Studio не вдалося намалювати: ${panel}";

  static String m184(panel) => "Не вдалося намалювати: ${panel}";

  static String m185(when) => "уперше ${when}";

  static String m186(mode) =>
      "замінює цей план; з require_approval «${mode}» кроки запису нового плану виконуються без людини";

  static String m187(v) => "v${v} розгорнуто";

  static String m188(v) => "v${v} · помилка";

  static String m189(v) => "v${v} зупинено";

  static String m190(v) => "Версія ${v}";

  static String m191(site) => "Потоки на ${site}";

  static String m192(count) => "Блоків: ${count}";

  static String m193(label) => "Відкріпити «${label}» від блока";

  static String m194(task, steps) =>
      "Виконай кроки, пропущені в плані завдання ${task}: ${steps}.";

  static String m195(n) =>
      "${n} не записано: ваші права вже сплили. Вони діють 5 хв після вашого останнього виклику в цій задачі; хід після запуску їх не поновлює.";

  static String m196(n) => "${n} не записано: це не ключ вузла.";

  static String m197(n) => "${n} не записано: задача тримає не більше 12.";

  static String m198(n) =>
      "${n} не записано: поза тим, що можете читати ви або агент.";

  static String m199(n) =>
      "${n} не записано: ваші права не були відомі (агент перезапустився, або запит їх не мав).";

  static String m200(address) => "з ${address}";

  static String m201(host, ms) => "${host} · відповів за ${ms} мс";

  static String m202(host) => "Немає відповіді від ${host}";

  static String m203(key) => "Перейти до ${key}";

  static String m204(id) => "Доступ для ${id}";

  static String m205(node) => "Розкажіть, що знаєте про ${node}…";

  static String m206(days) => "сирі дані ${days} д";

  static String m207(n) => "${n} рядів";

  static String m208(size) => "Історик ${size}";

  static String m209(id) => "Історія параметрів ${id}";

  static String m210(status) =>
      "Не вдалося прочитати історію: ${status}. Подробиці в «Проблемах».";

  static String m211(main, standby) => "${main} · резерв ${standby}";

  static String m212(n) =>
      "${Intl.plural(n, one: '1 вхід', few: '${n} входи', other: '${n} входів')}";

  static String m213(name, broker) => "${name} встановлено на ${broker}.";

  static String m214(n) =>
      "${Intl.plural(n, zero: 'у цьому флоу немає екземплярів', one: '1 екземпляр у цьому флоу', few: '${n} екземпляри в цьому флоу', other: '${n} екземплярів у цьому флоу')} · зміна тут змінює всі";

  static String m215(count) => "Скопійовано ключів: ${count}";

  static String m216(lag) => "відставання ${lag}";

  static String m217(time) => "останнє читання ${time}";

  static String m218(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m219(n) =>
      "${Intl.plural(n, one: '${n} лінк', few: '${n} лінки', other: '${n} лінків')}";

  static String m220(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m221(site) => "Лінки на ${site}";

  static String m222(first, last) => "${first} і ${last}";

  static String m223(status) =>
      "Не вдалося прочитати список дочірніх вузлів: ${status}. Подробиці в «Проблемах».";

  static String m224(n) =>
      "${Intl.plural(n, one: '1 зміна чекає в «Переглянути і застосувати»; її збережено.', few: '${n} зміни чекають у «Переглянути і застосувати»; їх збережено.', other: '${n} змін чекають у «Переглянути і застосувати»; їх збережено.')}";

  static String m225(reason) => "Шлюз відмовив: ${reason}.";

  static String m226(user, site, min) =>
      "${user} на ${site} · заблоковано після ${min} хв без дій. Значення і дерево приховано; лінки, потоки і сесія працюють далі.";

  static String m227(id) => "Журнал ${id}";

  static String m228(name) => "${name} (спосіб, якого ця Studio не знає)";

  static String m229(n) =>
      "${Intl.plural(n, one: 'його вживає 1 екземпляр', few: 'його вживають ${n} екземпляри', other: 'його вживають ${n} екземплярів')}";

  static String m230(n) => "бібліотека v${n}";

  static String m231(n) => "вжито: ${n}";

  static String m232(n) => "v${n}";

  static String m233(kind, count) => "${kind} · дій: ${count}";

  static String m234(status) =>
      "Не вдалося прочитати опис: ${status}. Подробиці в «Проблемах».";

  static String m235(n) =>
      "${Intl.plural(n, zero: 'Скласти план', one: 'Скласти план для 1 пристрою', few: 'Скласти план для ${n} пристроїв', other: 'Скласти план для ${n} пристроїв')}";

  static String m236(count) =>
      "${Intl.plural(count, one: '… ще ${count} байт', few: '… ще ${count} байти', other: '… ще ${count} байтів')}";

  static String m237(count) =>
      "${Intl.plural(count, one: 'ще ${count} рядок', few: 'ще ${count} рядки', other: 'ще ${count} рядків')}";

  static String m238(count) => "Вибрано: ${count}";

  static String m239(level, path) => "потрібен рівень ${level} на ${path}";

  static String m240(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m241(level) => "Потрібно ${level} · у вас є";

  static String m242(action) => "Цей вузол не має дії ${action}.";

  static String m243(param) => "Драйвер не має параметра ${param}.";

  static String m244(site) => "немає: ${site} — вершина";

  static String m245(site) => "підписано CA сайту ${site} (відомий)";

  static String m246(site) => "сертифікат CA сайту ${site}, закріплено";

  static String m247(version) => "wyrmd ${version}";

  static String m248(site) => "Дерево покаже wy/${site}.";

  static String m249(node) => "Відкрити ${node} в Explorer";

  static String m250(id) => "Відкрити tasks/${id}";

  static String m251(site) => "Відкриваємо дерево сайту ${site}…";

  static String m252(name) => "пакет ${name}";

  static String m253(n) =>
      "${Intl.plural(n, one: '1 випадок', few: '${n} випадки', other: '${n} випадків')}";

  static String m254(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m255(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m256(detail) => "Це не JSON: ${detail}";

  static String m257(n) =>
      "Додано ${n} ключів, найбільше для одного запиту. Спершу приберіть один.";

  static String m258(site) =>
      "Додайте вузол ${site} як @-чип: фільтруйте або введіть його ключ";

  static String m259(key) => "${key} поза тим, що агент може читати";

  static String m260(key) => "Додати ${key}";

  static String m261(site) => "${site} · вибрано в цій мережі";

  static String m262(site) =>
      "${site} · вибрано в цій мережі · резерв заповнено";

  static String m263(now, atRun) =>
      "чекає на схвалення · перевірено зараз: ${now}, під час виконання: ${atRun}";

  static String m264(n) => "потребує кроку ${n}";

  static String m265(path) =>
      "Збережено ${path}. Запустіть його через wyrm-agent run.";

  static String m266(steps) =>
      "Секретних аргументів у файлі немає: ${steps}. Додайте їх перед запуском.";

  static String m267(s) => "${s} с";

  static String m268(n) =>
      "${Intl.plural(n, one: 'План · ${n} крок', few: 'План · ${n} кроки', many: 'План · ${n} кроків', other: 'План · ${n} кроку')}";

  static String m269(s) => "тайм-аут ${s} с";

  static String m270(n) =>
      "${Intl.plural(n, one: '${n} точка', few: '${n} точки', other: '${n} точок')}";

  static String m271(n) =>
      "${Intl.plural(n, one: '1 порт', few: '${n} порти', other: '${n} портів')}";

  static String m272(step) => "${step} · пізніше";

  static String m273(site) => "Читання дерева сайту ${site}";

  static String m274(message) => "Чернетка не запускається: ${message}";

  static String m275(reason) =>
      "Недоступно: /api/info не відповів (${reason}).";

  static String m276(version) =>
      "Недоступно: цьому gateway потрібна Studio ${version} або новіша.";

  static String m277(count) =>
      "${Intl.plural(count, one: '1 проблема', few: '${count} проблеми', many: '${count} проблем', other: '${count} проблеми')}";

  static String m278(name) => "${name} встановлено";

  static String m279(name) => "Встановлення ${name}…";

  static String m280(sites) => "досягає ${sites}";

  static String m281(status) =>
      "Не вдалося прочитати значення: ${status}. Подробиці в «Проблемах».";

  static String m282(field) =>
      "Цей брокер не може прив\'язати ${field} (його рушій флоу старший за ADR 0040)";

  static String m283(field) => "${field} не має входу: введіть значення";

  static String m284(from, to) => "${from} не підходить до ${to}";

  static String m285(cn) => "Відхилити ${cn}?";

  static String m286(n) =>
      "${Intl.plural(n, one: 'ретранслює ${n} сайт', few: 'ретранслює ${n} сайти', other: 'ретранслює ${n} сайтів')}";

  static String m287(id) => "Видалити ${id}?";

  static String m288(name) => "Видалити ${name}?";

  static String m289(id) =>
      "Цей план замінило завдання tasks/${id}, і його не можна схвалити. Схваліть план того завдання.";

  static String m290(action) => "Результат · ${action}";

  static String m291(what) => "повертає ${what}";

  static String m292(audit) =>
      "Кожен запис перевіряє лінк і фіксує в ${audit}. Значення зʼявляється лише після зворотного читання.";

  static String m293(rev) => "Ревізія ${rev}";

  static String m294(rev) => "Ревізія ${rev} · діє";

  static String m295(n) => "${n} MiB";

  static String m296(n) => "${n} мс";

  static String m297(path) => "на ${path}";

  static String m298(site, user, role, level) =>
      "Сайт ${site} · застосовується з вашими правами: ${user}, ${role} (${level})";

  static String m299(role, site) => "${role} на ${site}";

  static String m300(rev) => "Повернути ревізію ${rev}?";

  static String m301(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m302(site, broker) => "З ${site} · wyrmd ${broker}";

  static String m303(when, n, sealed) =>
      "Створено ${when} · секцій: ${n} · секрети: ${sealed}";

  static String m304(fresh, exists) =>
      "Лінки: нових ${fresh}, наявних тут ${exists}";

  static String m305(site) => "Копія іншого сайту: ${site}";

  static String m306(files) => "Замінити ключі сайту: ${files}";

  static String m307(site) => "${site} перезапускається і застосовує копію";

  static String m308(site) => "Відновити ${site} з резервної копії";

  static String m309(done, size) => "Вивантаження: ${done} з ${size}";

  static String m310(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m311(s) => "усі кроки пройшли · ${s} с";

  static String m312(steps) => "виконано · пропущені кроки: ${steps}";

  static String m313(steps) =>
      "зупинено · кроки ${steps} щось змінили й лишаються виконаними";

  static String m314(n) =>
      "зупинено · крок ${n} щось змінив і лишається виконаним";

  static String m315(n, of) => "Виконання · крок ${n} з ${of}";

  static String m316(of) => "Виконання · кроків: ${of}";

  static String m317(site) => "Працює на ${site}";

  static String m318(task) => "Зберегти план завдання ${task}";

  static String m319(name) => "${name}";

  static String m320(date) => "додано ${date}";

  static String m321(site) =>
      "Встановлено ${site} (gateway.devices.step_up: config); тут це не вимкнути.";

  static String m322(site) =>
      "${site} цього не просить (gateway.devices.step_up: none); увімкнути може лише шлюз.";

  static String m323(site) => "Ваші пристрої на ${site}";

  static String m324(n) =>
      "${Intl.plural(n, zero: 'пароль потрібен сьогодні', one: 'пароль потрібен за 1 день', few: 'пароль потрібен за ${n} дні', other: 'пароль потрібен за ${n} днів')}";

  static String m325(site, max) =>
      "Приховує дерево і значення; сесію і «Переглянути і застосувати» збережено. ${site} дозволяє щонайбільше ${max} хв.";

  static String m326(n) => "${n} хв";

  static String m327(device) => "На ${device}";

  static String m328(site) => "${site} просить ваш пароль перед новим ключем.";

  static String m329(site, state, max, days, confirm) =>
      "Політика ${site}: пристрої ${state} · до ${max} · пароль кожні ${days} днів${confirm}. Адміністратор бачить і видаляє пристрої в Доступ › Користувачі.";

  static String m330(admin) => "видалив ${admin}";

  static String m331(user) =>
      "Усі сесії й усі пристрої ${user} завершуються, цей теж.";

  static String m332(store, date, device) =>
      "Ключ у ${store}, додано ${date}. Вимкнення видаляє ключ тут і ${device} з ваших пристроїв.";

  static String m333(store) =>
      "Вимкнено: Studio тут питає пароль. Увімкнення створює ключ у ${store}.";

  static String m334(s) => "${s} с";

  static String m335(level) => "Рівень журналу ${level}";

  static String m336(site) => "Сайти навколо ${site}";

  static String m337(site) =>
      "До чого під’єднаний ${site} і що під’єднано до нього: брокери вище й нижче, платформи, куди він надсилає, і пристрої, чиї лінки працюють поза брокером.";

  static String m338(count) =>
      "${Intl.plural(count, one: '${count} байт', few: '${count} байти', other: '${count} байтів')}";

  static String m339(count) =>
      "${Intl.plural(count, one: '${count} символ', few: '${count} символи', other: '${count} символів')}";

  static String m340(count) =>
      "${Intl.plural(count, one: '${count} стовпець', few: '${count} стовпці', other: '${count} стовпців')}";

  static String m341(count) =>
      "${Intl.plural(count, one: '${count} елемент', few: '${count} елементи', other: '${count} елементів')}";

  static String m342(count) =>
      "${Intl.plural(count, one: '${count} ключ', few: '${count} ключі', other: '${count} ключів')}";

  static String m343(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m344(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m345(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m346(was) => "підготовлено · було ${was}";

  static String m347(host) => "Резерв: ${host}";

  static String m348(n, total) => "Крок ${n} з ${total}";

  static String m349(host) => "З’єднання з ${host}";

  static String m350(n) => "пропущено: потрібен крок ${n}";

  static String m351(name) => "Підтвердити через ${name}";

  static String m352(name, site, device) =>
      "${name} підписує лише цей запит: ${site} отримує доказ, прив’язаний до цих змін, і лишається підтвердженим на ${device} 5 хвилин.";

  static String m353(site) =>
      "${site} не прийняв підтвердження: ключ більше не відкривається";

  static String m354(n, site) =>
      "${Intl.plural(n, one: 'Застосувати 1 зміну на ${site}.', few: 'Застосувати ${n} зміни на ${site}.', other: 'Застосувати ${n} змін на ${site}.')} ${site} просить свіже підтвердження перед змінами рівня config.";

  static String m355(site) =>
      "Введіть пароль: ${site} лишається підтвердженим 5 хвилин.";

  static String m356(site, reason) =>
      "${site} не прийняв підтвердження: ${reason}";

  static String m357(name) =>
      "${name} не підтвердив. Спробуйте ще раз або введіть пароль.";

  static String m358(name) => "Очікування ${name}…";

  static String m359(n) => "Зупинено на кроці ${n}";

  static String m360(n, code) => "Зупинено на кроці ${n} · ${code}";

  static String m361(why) =>
      "${why}\nЗроблене до нього лишається; ніщо не скасовується само.";

  static String m362(version, os) => "${version} (${os})";

  static String m363(version, language) => "Studio ${version} · ${language}";

  static String m364(n) => "Відмов ACL побільшало на ${n}";

  static String m365(from) =>
      "acl_denied дорівнював ${from}, коли цей екран показували востаннє";

  static String m366(n) => "Резерв відстає на ${n} записів";

  static String m367(n) => "Відкладено розгалужень після розколу: ${n}";

  static String m368(site) => "${site} чекає на Authorize";

  static String m369(n) => "Нижчий брокер, що ретранслює сайтів: ${n}";

  static String m370(id) =>
      "sys/links/${id}/state має стан failed; причина в його журналі";

  static String m371(id) => "${id} не працює";

  static String m372(name) =>
      "${name} чекає в карантині, ця Studio не прочитала запис";

  static String m373(cn) => "${cn} чекає в карантині";

  static String m374(cn) => "Невідомий сертифікат CN ${cn}";

  static String m375(cn, t) => "Невідомий сертифікат CN ${cn} від ${t}";

  static String m376(size) =>
      "Усе, чим володіє брокер, лежить у його `data_dir` (тут ${size}). Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:";

  static String m377(n) =>
      "Наборів записів, відкладених після того, як обидва брокери були активні (усунений розкол): ${n}. Запис аудиту `standby_forked` каже які.";

  static String m378(n) =>
      "Записів реєстру, яких ще немає на резерві: ${n}. Перемикання зараз їх втратить.";

  static String m379(n) => "Очистити від’єднані лінки (${n})…";

  static String m380(ids) =>
      "${ids}\n\nЇхні id вибувають і більше не можуть бути використані.";

  static String m381(n) => "Очистити від’єднані лінки: ${n}…";

  static String m382(ids) => "Вилучено: ${ids}";

  static String m383(title) => "Копіювати: ${title}";

  static String m384(url) => "Посилання на посібник скопійовано: ${url}";

  static String m385(id) => "лінк: ${id}";

  static String m386(n) => "Скопійовано рядків: ${n}";

  static String m387(detail) => "Відповідь не є журналом (${detail}).";

  static String m388(path) => "Збережено ${path}";

  static String m389(n) =>
      "Рядків із кільця брокера: ${n} · новіші зверху · `sys/~act/get_log`";

  static String m390(n, m, time) =>
      "Рядків у межах 2 хв від ${time} UTC: ${n} з ${m} · новіші зверху · `sys/~act/get_log`";

  static String m391(t) => "запущено ${t}";

  static String m392(n) => "Потребує уваги · ${n}";

  static String m393(m, time) =>
      "Серед найновіших ${m} рядків немає жодного в межах 2 хв від ${time} UTC. Запитайте більше рядків або очистьте час.";

  static String m394(standby) =>
      "2. У `wyrmd.json5` на обох хостах: `${standby}` і `peers.listen`; радимо `arbiter` оренди на третьому хості.";

  static String m395(t) => "${t} · зараз";

  static String m396(n) => "з ${n}";

  static String m397(name) =>
      "Файл ${name}. Файл .cbor надсилається як є; файл JSON спершу кодується.";

  static String m398(name) => "Профіль ${name} додано";

  static String m399(name) => "Профіль ${name} вилучено";

  static String m400(reason) =>
      "Цей брокер не віддає перелік профілів через шлюз (${reason}). Профіль усе одно можна додати; брокер віддаватиме його як pub/<name>.";

  static String m401(name) => "Вилучити профіль ${name}";

  static String m402(name) =>
      "Брокер перестає віддавати pub/${name} і записує це в журнал аудиту (profile_remove).";

  static String m403(cn) => "зовнішній · CN ${cn}";

  static String m404(size) => "історія ${size} · відкрити Історію";

  static String m405(id) => "${id} не працює · відкрити Лінки";

  static String m406(site) => "${site} · відкрити Сайти";

  static String m407(cn) => "${cn} чекає · відкрити Карантин";

  static String m408(measure, from, to) =>
      "${measure} на вхід і вихід за секунду від ${from} до ${to}";

  static String m409(shown, total) => "${shown} з ${total} рядків";

  static String m410(up) => "нижче ${up}";

  static String m411(level) => "потрібно ${level}";

  static String m412(who) => "від ${who}";

  static String m413(n) => "помилка на кроці ${n}";

  static String m414(agent) => "Кожна задача — вузол: ${agent}/tasks/<id>";

  static String m415(id) => "замінено на ${id}";

  static String m416(who, op, key) => "${who} · ${op} ${key}";

  static String m417(point, range) => "${point} · останні ${range}";

  static String m418(site) => "TLS · сертифікат CA сайту ${site}";

  static String m419(site) => "TLS · CA сайту ${site}, ще не довірено";

  static String m420(site) =>
      "TLS · CA сайту ${site}, закріплено на цьому комп’ютері";

  static String m421(seconds) => "зникне через ${seconds} с";

  static String m422(site) => "лишається, доки ${site} не повернеться";

  static String m423(used, budget) => "${used} з ${budget} токенів";

  static String m424(site) => "Дерево · ${site}";

  static String m425(step) => "середнє за ${step}";

  static String m426(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m427(at, delta, key, over) =>
      "Δ від A (${at}): ${delta} ${key} за ${over}";

  static String m428(what, range) =>
      "${what}, ${range}. Виберіть діапазон вікном нижче.";

  static String m429(h, m) => "${h} год ${m} хв";

  static String m430(key) => "Ви не можете читати ${key}";

  static String m431(t) => "A · ${t}";

  static String m432(min, max) => "мін ${min} · макс ${max}";

  static String m433(m) => "${m} хв";

  static String m434(point) => "Тренд ${point}";

  static String m435(t) => "сирі · ${t}";

  static String m436(s) => "${s} с";

  static String m437(name) => "Показати або сховати ${name}";

  static String m438(n) => "${n} д";

  static String m439(n) => "${n} год";

  static String m440(n) => "${n} хв";

  static String m441(site) => "Збігається · довіряти ${site}";

  static String m442(host) =>
      "Сертифікат gateway не підписано цим CA, або він не називає ${host}. Нічому не довірено.";

  static String m443(site) => "Вперше на ${site} · перевірте сертифікат";

  static String m444(command) =>
      "На брокері: System › Gateway › Certificate code, або ${command} на його хості.";

  static String m445(site) =>
      "Gateway сайту ${site} має власний CA, якого цей комп’ютер не знає. Порівняйте код із кодом на брокері, перш ніж довіряти: будь-хто в цій мережі може оголосити ім’я.";

  static String m446(unit) => "адреса ${unit}";

  static String m447(name) => "${name} не відкрив ключ";

  static String m448(device) =>
      "Обличчя на ${device} змінилися, тож ключ, який зберігав Studio, більше не відкривається. Людина з новим обличчям не ввійде як ви.";

  static String m449(device) =>
      "Відбитки пальців на ${device} змінилися, тож ключ, який зберігав Studio, більше не відкривається. Людина з новим відбитком не ввійде як ви.";

  static String m450(name) => "${name} вимкнено для цього облікового запису";

  static String m451(site) => "Перевірка ключа на ${site}…";

  static String m452(site) => "підтвердити зміни на ${site}";

  static String m453(days, name) =>
      "Від останнього пароля тут минуло ${days} днів. Після цього входу ${name} знову працює.";

  static String m454(site, days) => "${site} просить пароль кожні ${days} днів";

  static String m455(site, user) => "увімкнути відмикання ${site} як ${user}";

  static String m456(site, days) =>
      "${site} просить пароль раз на ${days} днів.";

  static String m457(site) =>
      "Працює з ${site}. Інші шлюзи просять свій власний.";

  static String m458(site, standby) =>
      "Працює з ${site} і його резервним ${standby}. Інші шлюзи просять свій власний.";

  static String m459(user, site, store) =>
      "Один ключ для ${user} на ${site}, створений у ${store}. Він ніколи звідти не виходить; Studio ніколи не зберігає ваш пароль.";

  static String m460(name) =>
      "Увійдіть з паролем. ${name} лишається ввімкненим на наступний раз.";

  static String m461(store, date) => "Ключ у ${store} · додано ${date}";

  static String m462(name, when) => "${name} · ${when}";

  static String m463(name) => "${name} не збігся 3 рази";

  static String m464(site) => "до шлюзу ${site}.";

  static String m465(site) =>
      "${site} більше не дозволяє біометричне відмикання";

  static String m466(name) => "Не вдалося ввімкнути ${name}";

  static String m467(site, user, role) => "Вхід у ${site} як ${user} · ${role}";

  static String m468(name, site, device) =>
      "Замість пароля ${name} відкриває ключ, який доводить ${site}, що на ${device} саме ви.";

  static String m469(name) => "Наступного разу відмикати через ${name}?";

  static String m470(user) => "Пароль для ${user}";

  static String m471(host) => "${host} + резервний";

  static String m472(site, max) =>
      "${site} це дозволяє: біометричні пристрої увімкнено, до ${max} на користувача (gateway.devices). Вимкнути можна в меню облікового запису › Безпека.";

  static String m473(site, user) => "увійти в ${site} як ${user}";

  static String m474(name) => "Знову ввімкнути ${name} після входу";

  static String m475(device, name) =>
      "Адміністратор видалив ${device} з ваших пристроїв. Увійдіть з паролем; потім можна знову ввімкнути ${name}.";

  static String m476(role, site) => "· ${role} на ${site}";

  static String m477(site) => "Відімкніть, щоб відкрити дерево ${site}.";

  static String m478(device, name) =>
      "Шлюз більше не має запису про ${device}. Увійдіть з паролем; потім можна знову ввімкнути ${name}.";

  static String m479(site) => "${site} не знає цього ключа";

  static String m480(name) => "Використати ${name}";

  static String m481(name) => "Відімкнути через ${name}";

  static String m482(d) => "працює ${d}";

  static String m483(n) => "Оновити лінків: ${n}";

  static String m484(version) => "${version} залишається, лінк не відповів";

  static String m485(package) =>
      "Дайте zip пакета ${package} з вищою версією. Брокер перевіряє його як будь-яке встановлення і оновлює всі лінки пакета.";

  static String m486(links) => "Гарячий старт, без перезапуску: ${links}";

  static String m487(version, when) =>
      "${version} залишається встановленою до ${when}. Точка відновлення запечатана для цього брокера і залишається на ньому.";

  static String m488(n) => "лінків: ${n}";

  static String m489(n, links) => "Лінки, що перезапускаються (${n}): ${links}";

  static String m490(link) => "Відкрити ${link}";

  static String m491(link) => "${link} · перед відновленням з резервної копії";

  static String m492(link, version) =>
      "${link} · ${version} · перед оновленням";

  static String m493(version, links) =>
      "Ці лінки зупиняться і запустяться на ${version}: ${links}. Брокер повертає їхні приватні дані до точки відновлення оновлення, якщо оновлення змінило формат сховища або закінчилося погано; після вдалого оновлення вони зберігають поточні дані. Після цього жодна версія не зберігається: другого відкату немає.";

  static String m494(package, version) => "Відкотити ${package} до ${version}?";

  static String m495(version) => "Відкотити до ${version}…";

  static String m496(version) => "Відкочено до ${version}";

  static String m497(version) => "Лінки працюють на ${version}";

  static String m498(links) => "${links}: повернулися з усіма вузлами.";

  static String m499(state) => "Він змінює формат сховища (зі state ${state})";

  static String m500(state) => "Формат сховища: той самий (state ${state})";

  static String m501(back, gone) =>
      "оголошено знову: ${back} · ще немає або зникло: ${gone}";

  static String m502(n) => "Власний пакет · лінків на ньому: ${n}";

  static String m503(n) => "Пакет репозиторію · лінків на ньому: ${n}";

  static String m504(package, from, to) => "Оновити ${package} ${from} → ${to}";

  static String m505(package, from) => "Оновити ${package} ${from} з файлу";

  static String m506(package) => "${package} оновлено";

  static String m507(package) => "Оновлення ${package} відкочено";

  static String m508(result) => "Брокер завершив його як «${result}»";

  static String m509(package) => "Оновлення ${package}";

  static String m510(package) => "Версії ${package}";

  static String m511(version) => "Що нового у ${version}";

  static String m512(v) => "Версія ${v} · розгорнута";

  static String m513(site) => "через ${site}";

  static String m514(delimiter, header) =>
      "Так, як його читає блок: роздільник ${delimiter}, ${header}";

  static String m515(keys) => "${keys} зберігає · Esc скасовує";

  static String m516(keys) => "${keys} зберігає · Esc відкидає зміни";

  static String m517(n, who) => "${n} чекають на допуск: ${who}";

  static String m518(value) => "було ${value}";

  static String m519(n) => "Групи спостереження · ${n}";

  static String m520(mode) =>
      "З require_approval «${mode}» план вибраного варіанта виконує кроки запису без людини. Мітка — здогад асистента, а не перевірка. Прочитайте плитку, перш ніж вибрати її.";

  static String m521(user) => "Вітаємо, ${user}";

  static String m522(value) => "запустив би на ${value}";

  static String m523(value) => "надіслав би ${value}";

  static String m524(value) => "записав би ${value}";

  static String m525(level) => "Щоб увімкнути, потрібен рівень ${level}";

  static String m526(site) => "wyrmd на ${site}";

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
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "answerWaitingNote": MessageLookupByLibrary.simpleMessage(
      "Асистент чекає на вашу відповідь. До неї нічого не планується. Перезапуск брокера завершує завдання, що чекає.",
    ),
    "apiKeyNotSet": MessageLookupByLibrary.simpleMessage("не задано"),
    "apiKeySet": MessageLookupByLibrary.simpleMessage(
      "задано · ніколи не показується",
    ),
    "apiKeyUnknown": m7,
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "applyChanges": m8,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Застосувати профіль"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveByAgent": m9,
    "approveCount": m10,
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "approveNone": MessageLookupByLibrary.simpleMessage(
      "Позначте хоча б один крок.",
    ),
    "approveOtherSite": m11,
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення в Studio з\'явиться з наступним кроком. Поки що схвалюй через wyrm-agent.",
    ),
    "approveRefused": m12,
    "approveRefusedHint": MessageLookupByLibrary.simpleMessage(
      "Зніміть позначку з названого кроку й схваліть решту. Коли план виконано, попросіть пропущені кроки окремим завданням: їх схвалюють тоді.",
    ),
    "approveReveal": m13,
    "approveSigns": m14,
    "areaCoil": MessageLookupByLibrary.simpleMessage("Coil"),
    "areaDiscrete": MessageLookupByLibrary.simpleMessage("DI"),
    "areaHolding": MessageLookupByLibrary.simpleMessage("HR"),
    "areaInput": MessageLookupByLibrary.simpleMessage("IR"),
    "argsMasked": MessageLookupByLibrary.simpleMessage(
      "Схема цього кроку ще невідома (його вузол створює попередній крок): аргументи приховано, і жоден не потрапить у збережений план.",
    ),
    "askAdminFor": m15,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має виклику, щоб надіслати запит адміністратору.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Запитати"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну або постав питання про мережу (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("просить приєднатися"),
    "asksToJoinRelays": m16,
    "asksToRelay": m17,
    "auditDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "Аудит потребує рівня config на sys/audit.",
    ),
    "auditRefused": m18,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "backupPassphrase": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза копії",
    ),
    "backupPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Лише для копії, запечатаної парольною фразою. Копія, запечатана для свого сайту, фрази не потребує і відкривається лише на брокері з ключами того сайту. Studio її не зберігає.",
    ),
    "backupReplaces": m19,
    "backupRightsAsk": MessageLookupByLibrary.simpleMessage(
      "брокер запитає за потреби",
    ),
    "backupRightsNote": MessageLookupByLibrary.simpleMessage(
      "Потрібно, коли лінк має права або список дозволених мереж: без цього брокер показує їх і нічого не встановлює. Токен, сертифікат і ключ запитувача будуть нові.",
    ),
    "bakAbout": m20,
    "bakAll": MessageLookupByLibrary.simpleMessage("Усе"),
    "bakBackUp": MessageLookupByLibrary.simpleMessage("Створити копію…"),
    "bakCancelDownload": MessageLookupByLibrary.simpleMessage(
      "Скасувати завантаження",
    ),
    "bakCard": MessageLookupByLibrary.simpleMessage("Резервні копії"),
    "bakCardEmpty": MessageLookupByLibrary.simpleMessage(
      "На брокері немає резервних копій.",
    ),
    "bakCardNote": m21,
    "bakCardOld": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має резервних копій зі Studio (на ньому wyrmd до ADR 0048). Скористайтеся командами нижче.",
    ),
    "bakChooseConnection": MessageLookupByLibrary.simpleMessage(
      "Виберіть лінк і з\'єднання",
    ),
    "bakChooseFolder": m22,
    "bakConsistent": MessageLookupByLibrary.simpleMessage(
      "Кожне сховище читається в один узгоджений момент, у власній транзакції читання; брокер працює і записує далі.",
    ),
    "bakDo": MessageLookupByLibrary.simpleMessage("Створити копію"),
    "bakDoLink": m23,
    "bakDoneSub": m24,
    "bakDoneTitle": MessageLookupByLibrary.simpleMessage(
      "Резервна копія готова",
    ),
    "bakDownload": MessageLookupByLibrary.simpleMessage("Завантажити…"),
    "bakDownloading": m25,
    "bakFactBy": MessageLookupByLibrary.simpleMessage("Створив"),
    "bakFactContents": MessageLookupByLibrary.simpleMessage("Вміст"),
    "bakFactLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "bakFactSealed": MessageLookupByLibrary.simpleMessage("Секрети"),
    "bakFactSent": MessageLookupByLibrary.simpleMessage("Надіслано до"),
    "bakFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер не створив резервну копію",
    ),
    "bakFailedTitle": m26,
    "bakKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Введіть нижче парольну фразу щонайменше з 12 символів: нею запечатуються ключі.",
    ),
    "bakKeysNeverSent": MessageLookupByLibrary.simpleMessage(
      "Резервну копію з ключами й секретами не надсилають: завантажте її на власному шлюзі сайту.",
    ),
    "bakKeysWarning": m27,
    "bakKindFull": MessageLookupByLibrary.simpleMessage("брокер"),
    "bakKindLink": m28,
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
    "bakNotRead": MessageLookupByLibrary.simpleMessage(
      "Брокер описав свої резервні копії у формі, яку ця Studio не читає, тому тут їх не запропоновано. Поле вказано в журналі; дивись Проблеми.",
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
    "bakPassphraseShort": m29,
    "bakProgressSub": MessageLookupByLibrary.simpleMessage(
      "Можна закрити; брокер завершить і збереже її в резервних копіях.",
    ),
    "bakProgressTitle": m30,
    "bakRemoveNote": MessageLookupByLibrary.simpleMessage(
      "Файл видаляється з брокера. Завантажена чи надіслана копія залишається.",
    ),
    "bakRemoveRow": MessageLookupByLibrary.simpleMessage(
      "Видалити її з брокера",
    ),
    "bakRemoveTitle": m31,
    "bakRestore": MessageLookupByLibrary.simpleMessage("Відновити…"),
    "bakRowFailed": MessageLookupByLibrary.simpleMessage("помилка"),
    "bakRowNotRead": MessageLookupByLibrary.simpleMessage(
      "не прочитано: у формі, якої ця Studio не знає",
    ),
    "bakRowRunning": m32,
    "bakRowSending": m33,
    "bakSaved": m34,
    "bakSavedNote": m35,
    "bakSavedTo": m36,
    "bakSealedBroker": m37,
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
    "bakSendFailed": m38,
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
    "bakSending": m39,
    "bakSensitive": MessageLookupByLibrary.simpleMessage(
      "Резервна копія така ж чутлива, як каталог даних брокера: тримайте її там, куди мають доступ лише адміністратори.",
    ),
    "bakShow": MessageLookupByLibrary.simpleMessage(
      "Показати в резервних копіях",
    ),
    "bakStepWriting": MessageLookupByLibrary.simpleMessage("Запис файлу"),
    "bakSub": MessageLookupByLibrary.simpleMessage(
      "Виберіть, що потрапить у файл. Один файл .wyrm-backup (zip із маніфестом); брокер працює, поки його створюють.",
    ),
    "bakSubLink": m40,
    "bakTagAlways": MessageLookupByLibrary.simpleMessage("завжди"),
    "bakTagPassphrase": MessageLookupByLibrary.simpleMessage("парольна фраза"),
    "bakTagSite": MessageLookupByLibrary.simpleMessage(
      "запечатано для цього сайту",
    ),
    "bakTitle": m41,
    "bakTitleLink": m42,
    "bakWhatGoesIn": MessageLookupByLibrary.simpleMessage(
      "Що потрапляє у файл",
    ),
    "bakWhere": MessageLookupByLibrary.simpleMessage("Куди"),
    "bakWhereBroker": MessageLookupByLibrary.simpleMessage(
      "Залишити на брокері",
    ),
    "bakWhereBrokerNote": m43,
    "bakWhereComputer": MessageLookupByLibrary.simpleMessage("Цей комп\'ютер"),
    "bakWhereComputerNote": m44,
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
    "blocksCount": m45,
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
    "brokersDevices": m46,
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m47,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "bupBackOn": m48,
    "bupBackOnNote": m49,
    "bupCard": MessageLookupByLibrary.simpleMessage("Версія брокера"),
    "bupCardAvailable": m50,
    "bupCardCurrent": m51,
    "bupCardRolledBack": m52,
    "bupCardTrial": m53,
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
    "bupCheckSchemaNote": m54,
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
    "bupDoneRestart": m55,
    "bupDoneStaged": m56,
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
    "bupLinksBack": m57,
    "bupLost": m58,
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
    "bupOpenLog": m59,
    "bupPillContainer": MessageLookupByLibrary.simpleMessage("контейнер"),
    "bupPillRestarting": MessageLookupByLibrary.simpleMessage("перезапуск"),
    "bupReconnecting": MessageLookupByLibrary.simpleMessage("Під\'єднання…"),
    "bupRestarting": m60,
    "bupRollBackNote": MessageLookupByLibrary.simpleMessage(
      "Брокер перезапуститься на попередній версії й відновить копію площини керування, зроблену перед оновленням. Зміни після оновлення втрачаються.",
    ),
    "bupRollBackTitle": m61,
    "bupRollBackUntil": m62,
    "bupRolledBack": MessageLookupByLibrary.simpleMessage(
      "Оновлення відкочено",
    ),
    "bupRuns": m63,
    "bupRunsNote": m64,
    "bupSeconds": m65,
    "bupShow": MessageLookupByLibrary.simpleMessage("Показати…"),
    "bupStep1": MessageLookupByLibrary.simpleMessage(
      "Резервна копія площини керування перед оновленням, секрети запечатано (зберігається до підтвердження оновлення).",
    ),
    "bupStep2": m66,
    "bupStep3": m67,
    "bupStep4": m68,
    "bupStep5": m69,
    "bupSub": MessageLookupByLibrary.simpleMessage(
      "З каналу випусків цього брокера · брокер перезапускається один раз",
    ),
    "bupTitle": m70,
    "bupType": m71,
    "bupUpdate": MessageLookupByLibrary.simpleMessage("Оновити…"),
    "bupUpdated": m72,
    "bupUpdating": m73,
    "bupUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Цей екран під\'єднується самостійно.",
    ),
    "caSigned": m74,
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
    "cbNote": m75,
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
    "changesGuess": m76,
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
    "childCount": m77,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Вибери рядок: вузол відкривається в дереві, значення — в інспекторі.",
    ),
    "chkAfterDownload": MessageLookupByLibrary.simpleMessage(
      "брокер перевіряє після завантаження",
    ),
    "chkArchive": MessageLookupByLibrary.simpleMessage("Архів"),
    "chkAsNewLink": MessageLookupByLibrary.simpleMessage(
      "брокер перевіряє як новий лінк",
    ),
    "chkBackupParts": MessageLookupByLibrary.simpleMessage(
      "Архів, маніфест, лінк",
    ),
    "chkBinaries": MessageLookupByLibrary.simpleMessage("Виконувані файли"),
    "chkComponent": MessageLookupByLibrary.simpleMessage("Компонент"),
    "chkComponentMissing": m78,
    "chkDownload": MessageLookupByLibrary.simpleMessage("Завантаження"),
    "chkEntries": m79,
    "chkEntryMissing": m80,
    "chkFetched": m81,
    "chkFetchedIt": MessageLookupByLibrary.simpleMessage(
      "його завантажує брокер",
    ),
    "chkKib": m82,
    "chkKibAndFiles": m83,
    "chkKind": MessageLookupByLibrary.simpleMessage("Вид"),
    "chkLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "chkLinkFrom": m84,
    "chkLinkParts": MessageLookupByLibrary.simpleMessage(
      "Визначення, права, файли пакета",
    ),
    "chkManifest": MessageLookupByLibrary.simpleMessage("Маніфест"),
    "chkMissing": m85,
    "chkMissingFields": m86,
    "chkNameVersion": MessageLookupByLibrary.simpleMessage("Назва і версія"),
    "chkNameVersionBad": m87,
    "chkNeedsEntries": MessageLookupByLibrary.simpleMessage(
      "пакет-процес потребує файлу для кожного хоста",
    ),
    "chkNoEntryFor": m88,
    "chkNoManifest": m89,
    "chkNoSecrets": MessageLookupByLibrary.simpleMessage("у файлі їх немає"),
    "chkNone": MessageLookupByLibrary.simpleMessage("(немає)"),
    "chkNotJson": m90,
    "chkNotJsonAt": m91,
    "chkNotObject": m92,
    "chkNotReadHere": m93,
    "chkNotWasm": MessageLookupByLibrary.simpleMessage("це не WebAssembly"),
    "chkNotWasmFile": m94,
    "chkNotZip": MessageLookupByLibrary.simpleMessage("це не zip"),
    "chkOtherKind": m95,
    "chkPackage": MessageLookupByLibrary.simpleMessage("Пакет"),
    "chkPackageInFile": m96,
    "chkPackageNotInFile": m97,
    "chkPathNotRelative": m98,
    "chkPaths": MessageLookupByLibrary.simpleMessage("Шляхи"),
    "chkPathsOk": MessageLookupByLibrary.simpleMessage(
      "відносні, без посилань",
    ),
    "chkProtocol": MessageLookupByLibrary.simpleMessage("Протокол"),
    "chkProtocolOk": m99,
    "chkProtocolOther": m100,
    "chkRemoteParts": MessageLookupByLibrary.simpleMessage(
      "Архів, маніфест, виконувані файли",
    ),
    "chkRightsAsked": MessageLookupByLibrary.simpleMessage("Запитані права"),
    "chkSealedForSite": m101,
    "chkSealedPassphrase": MessageLookupByLibrary.simpleMessage(
      "запечатано паролем",
    ),
    "chkSecrets": MessageLookupByLibrary.simpleMessage("Секрети"),
    "chkSections": MessageLookupByLibrary.simpleMessage("Секції"),
    "chkSize": MessageLookupByLibrary.simpleMessage("Розмір"),
    "chkSizeAndFiles": MessageLookupByLibrary.simpleMessage("Розмір і файли"),
    "chkSymbolicLink": m102,
    "chkThisHost": MessageLookupByLibrary.simpleMessage("Цей хост"),
    "chkTooDeep": m103,
    "chkTooLarge": m104,
    "chkTooLargeZipped": m105,
    "chkTooManyFiles": m106,
    "chkUnknownField": m107,
    "chkUnknownFields": m108,
    "chkUnknownName": m109,
    "chkWasm": MessageLookupByLibrary.simpleMessage("WebAssembly"),
    "chkWorld": MessageLookupByLibrary.simpleMessage("World"),
    "chkWorldByBroker": MessageLookupByLibrary.simpleMessage(
      "брокер читає його з компонента",
    ),
    "chkWrongForm": m110,
    "choicesConfirm": MessageLookupByLibrary.simpleMessage("Написати план"),
    "choicesFromCard": m111,
    "choicesNoAnswer": MessageLookupByLibrary.simpleMessage("без відповіді"),
    "choicesNote": MessageLookupByLibrary.simpleMessage(
      "Або дайте відповідь своїми словами нижче.",
    ),
    "choicesOwnWords": m112,
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
    "connectNote": m113,
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
    "dataDir": m114,
    "dataflow": MessageLookupByLibrary.simpleMessage("Потік даних"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Його права тут забрано зараз, наступне з’єднання чекатиме в карантині. Його сайти лишаються під ним.",
    ),
    "deauthorizeTitle": m115,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Вирішити в Лінках"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Лінк у карантині схвалюють або відхиляють у Лінках › Карантин.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "deploy": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "deployAskMessage": m116,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage(
      "Розгорнути цей потік?",
    ),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Щоб розгорнути, повернися до флоу",
    ),
    "deployedByWho": m117,
    "deploying": MessageLookupByLibrary.simpleMessage("Розгортання…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Усі частини дизайн-системи (лише для розробки).",
    ),
    "deviceForgetText": MessageLookupByLibrary.simpleMessage(
      "Запис зникає зі шлюзу.",
    ),
    "deviceForgetTitle": m118,
    "deviceLine": m119,
    "deviceRemoveText": m120,
    "deviceRemoveTitle": m121,
    "devicesNone": MessageLookupByLibrary.simpleMessage("Пристроїв немає."),
    "disableUser": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнений користувач не може увійти; ролі лишаються.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discoverFound": m122,
    "discoverLooking": m123,
    "discoverNoneTitle": m124,
    "discoverNothing": MessageLookupByLibrary.simpleMessage(
      "Нічого не знайдено",
    ),
    "discoverPanel": MessageLookupByLibrary.simpleMessage(
      "Gateway у цій мережі",
    ),
    "discoverProbed": m125,
    "discoverProbing": m126,
    "doneLeftOutNote": m127,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "Задачу виконано. План і журнал лишаються в її записі.",
    ),
    "doneOnTheDevice": m128,
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
    "editParamsOf": m129,
    "enableUser": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "errAdviceBroker": m130,
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
    "errAdviceInputField": m131,
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
    "errAdviceRightsRole": m132,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо повторюється, перезапустіть Studio.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Цей брокер або лінк не має такого виклику; можливо, він старіший, ніж очікує Studio.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Назад до форми"),
    "errBackupDigestMismatch": MessageLookupByLibrary.simpleMessage(
      "Отриманий файл — не ця копія: його SHA-256 не той, що показує брокер. Нічого не збережено. Обидва значення є в журналі.",
    ),
    "errBackupNoDigest": MessageLookupByLibrary.simpleMessage(
      "Брокер не показує SHA-256 цієї копії, тому перевірити отримане неможливо. Нічого не збережено.",
    ),
    "errCallOn": m133,
    "errCheckNotRun": MessageLookupByLibrary.simpleMessage(
      "Файл не вдалося перевірити, тому встановлення не продовжується. Візьми інший файл.",
    ),
    "errChipStudio": m134,
    "errCopied": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage(
      "Копіювати подробиці",
    ),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Копіювати звіт"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Подробиці"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "Подробиці в буфері обміну.",
    ),
    "errDoDeploy": m135,
    "errDoInstall": m136,
    "errDoList": m137,
    "errDoLogIn": m138,
    "errDoOpen": m139,
    "errDoRead": m140,
    "errDoRemove": m141,
    "errDoRun": m142,
    "errDoSave": m143,
    "errDoStart": m144,
    "errDoStep": m145,
    "errDoStop": m146,
    "errDoWrite": m147,
    "errDoingDeploy": m148,
    "errDoingInstall": m149,
    "errDoingList": m150,
    "errDoingLogIn": m151,
    "errDoingOpen": m152,
    "errDoingRead": m153,
    "errDoingRemove": m154,
    "errDoingRun": m155,
    "errDoingSave": m156,
    "errDoingStart": m157,
    "errDoingStop": m158,
    "errDoingWrite": m159,
    "errFaultMessage": MessageLookupByLibrary.simpleMessage(
      "Тут стався збій у Studio. Це помилка Studio, а не брокера; більше нічого не надіслано.",
    ),
    "errFileNotRead": MessageLookupByLibrary.simpleMessage(
      "Цей файл не у формі, яку читає Studio, тому нічого не надіслано. Поле з помилкою вказано в журналі.",
    ),
    "errFileNotReadBecause": m160,
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
    "errNounRun": m161,
    "errNounSave": MessageLookupByLibrary.simpleMessage("збереження"),
    "errNounStart": MessageLookupByLibrary.simpleMessage("запуск"),
    "errNounStop": MessageLookupByLibrary.simpleMessage("зупинка"),
    "errNounWrite": MessageLookupByLibrary.simpleMessage("запис"),
    "errOpenLog": MessageLookupByLibrary.simpleMessage("Відкрити журнал"),
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
    "errSilentReach": m162,
    "errSilentStatus": m163,
    "errStatusLine": m164,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("це"),
    "errTimeLocal": m165,
    "errTitleBroker": m166,
    "errTitleBrokerNoSite": m167,
    "errTitleBusy": m168,
    "errTitleGone": m169,
    "errTitleHistory": m170,
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
    "errTitleReach": m171,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "Брокер не відповідає",
    ),
    "errTitleRead": m172,
    "errTitleRights": m173,
    "errTitleStream": m174,
    "errTitleStudio": m175,
    "errTitleUnsupported": m176,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще раз"),
    "errTryAgainIn": m177,
    "errUnreadableAnswer": MessageLookupByLibrary.simpleMessage(
      "Брокер відповів у формі, яку ця Studio не читає, тому тут нічого не змінено. Поле вказано в журналі.",
    ),
    "errUnreadableRows": MessageLookupByLibrary.simpleMessage(
      "Брокер відповів про ці записи у формі, яку ця Studio не читає, тому їх не показано. Решту показано. Поля вказано в журналі.",
    ),
    "errUserRole": m178,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("Що можна зробити"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "Запис, що не дочекався відповіді, міг бути застосований. Перевірте значення, перш ніж надсилати знову.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("ще не було"),
    "everySeconds": m179,
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
    "factVersionOf": m180,
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
    "fatalMoveFailed": m181,
    "fatalNote": m182,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Вийти зі Studio"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося запустити",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "Решта Studio працює; значення та дії в інших місцях не зачеплено.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Намалювати ще раз"),
    "faultProblem": m183,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("цю частину"),
    "faultTitle": m184,
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
    "fieldOffset": MessageLookupByLibrary.simpleMessage("Зсув"),
    "fieldPrecision": MessageLookupByLibrary.simpleMessage("Точність"),
    "fieldRegisters": MessageLookupByLibrary.simpleMessage("Регістри"),
    "fieldScale": MessageLookupByLibrary.simpleMessage("Масштаб"),
    "fieldUnit": MessageLookupByLibrary.simpleMessage("Одиниця"),
    "fieldWordOrder": MessageLookupByLibrary.simpleMessage("Порядок слів"),
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
    "firstSeen": m185,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "Чернетка не проходить перевірку.",
    ),
    "fixReplaces": MessageLookupByLibrary.simpleMessage("замінює цей план"),
    "fixReplacesModeUnknown": MessageLookupByLibrary.simpleMessage(
      "замінює цей план; невідомо, хто схвалює, тому кроки запису нового плану можуть виконатися без людини",
    ),
    "fixReplacesNoPerson": m186,
    "flowBack": MessageLookupByLibrary.simpleMessage("Назад"),
    "flowDeployed": m187,
    "flowError": m188,
    "flowName": MessageLookupByLibrary.simpleMessage("Ідентифікатор потоку"),
    "flowProblemUnknown": MessageLookupByLibrary.simpleMessage("помилка"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Кожне поле має значення, вхід і вихід. Введіть значення або перетягніть на нього будь-який вихід, щоб зв’язати.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле показує значення, яке надходить; його зв’язок і джерело світяться, коли на нього навести. Значок зв’язку веде до джерела або розв’язує.",
    ),
    "flowStateUnread": MessageLookupByLibrary.simpleMessage(
      "стан не прочитано",
    ),
    "flowStopped": m189,
    "flowVersion": m190,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "Розгортання потребує config на dataflows; gateway додає ваші докази для кожної цілі. Глядачі можуть лише дивитися.",
    ),
    "flowsOn": m191,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Кожен потік працює в брокері. Ви редагуєте чернетку; нічого не змінюється до розгортання.",
    ),
    "fmBlocks": m192,
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
    "fmUnpinField": m193,
    "followNeeds": MessageLookupByLibrary.simpleMessage(
      "продовжити це завдання може лише той, хто його поставив, або користувач з config на лінку агента",
    ),
    "followUpAsk": m194,
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
    "foundRefusedExpired": m195,
    "foundRefusedInvalid": m196,
    "foundRefusedLimit": m197,
    "foundRefusedOutside": m198,
    "foundRefusedUnknown": m199,
    "foundTitle": MessageLookupByLibrary.simpleMessage(
      "Що я знайшов · лише читання",
    ),
    "foundUncertain": MessageLookupByLibrary.simpleMessage("зараз непевно"),
    "fromAddress": m200,
    "fromBackup": MessageLookupByLibrary.simpleMessage("З резервної копії"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "Резервна копія лінка (.wyrm-link), створена дією «Резервна копія…» на лінку: налаштування, приватні дані й пакет. Повертається під своїм або новим ідентифікатором.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m201,
    "gatewayNoAnswer": m202,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Користувач gateway"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m203,
    "goToSource": MessageLookupByLibrary.simpleMessage("До джерела"),
    "goUp": MessageLookupByLibrary.simpleMessage("Вгору"),
    "grantFor": m204,
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
    "hintFailed": m205,
    "hintPlanning": MessageLookupByLibrary.simpleMessage(
      "Дайте відповідь або спитайте інше…",
    ),
    "hintRunning": MessageLookupByLibrary.simpleMessage(
      "Можна писати, поки він виконується…",
    ),
    "historianKeep": m206,
    "historianSeries": m207,
    "historianSize": m208,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Лінки синхронізації читають журнал змін історика, тож нічого не губиться, поки база недоступна.",
    ),
    "historyOf": m209,
    "historyRange1h": MessageLookupByLibrary.simpleMessage("1 год"),
    "historyRange24h": MessageLookupByLibrary.simpleMessage("24 год"),
    "historyRange30d": MessageLookupByLibrary.simpleMessage("30 д"),
    "historyRange7d": MessageLookupByLibrary.simpleMessage("7 д"),
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "історія недоступна",
    ),
    "historyUnavailableTip": m210,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "hostsWithStandby": m211,
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Імпорт CSV або дерева DSA",
    ),
    "inputsCount": m212,
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
    "installedOn": m213,
    "instancesInFlow": m214,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Видати"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Ключ скопійовано"),
    "keysCopied": m215,
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
    "lag": m216,
    "languageName": MessageLookupByLibrary.simpleMessage("Українська"),
    "lastRead": m217,
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
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksAlready": m218,
    "linksCount": m219,
    "linksLocalNote": m220,
    "linksOn": m221,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "listAnd": m222,
    "listFailedTip": m223,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "Ви не можете читати всі джерела й цілі цього потоку",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "lockKept": m224,
    "lockRefused": m225,
    "lockText": m226,
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
    "logOf": m227,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "logTypeAllData": MessageLookupByLibrary.simpleMessage("Усі дані"),
    "logTypeInterval": MessageLookupByLibrary.simpleMessage("Інтервал"),
    "logTypeNone": MessageLookupByLibrary.simpleMessage("Нічого"),
    "logTypeOther": m228,
    "logTypePointChange": MessageLookupByLibrary.simpleMessage("Зміна точки"),
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
    "mbInUse": m229,
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
    "mbUpdateTo": m230,
    "mbUsed": m231,
    "mbVersion": m232,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Мова"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Інше"),
    "menuSubtitle": m233,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Тема"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Повідомлень роутера за секунду",
    ),
    "metaFailedTip": m234,
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
    "moreButton": m235,
    "moreBytes": m236,
    "moreLines": m237,
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
    "nSelected": m238,
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
    "needsLevelOn": m239,
    "needsLevelYouHave": m240,
    "needsLevelYouHaveIt": m241,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newCertificate": MessageLookupByLibrary.simpleMessage("новий сертифікат"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("Новий потік"),
    "newTask": MessageLookupByLibrary.simpleMessage("Нова задача"),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "no": MessageLookupByLibrary.simpleMessage("ні"),
    "noActionReason": m242,
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
    "noParamReason": m243,
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
    "noUpstream": m244,
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
    "noteKnownAs": m245,
    "noteNew": MessageLookupByLibrary.simpleMessage(
      "власний CA · перевірте код, перш ніж довіряти",
    ),
    "notePinned": m246,
    "notePlain": MessageLookupByLibrary.simpleMessage(
      "простий http на цьому комп’ютері",
    ),
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "Точка дерева. Точка лише для читання не має входу; зв’язок у записувану точку пише ~set.",
    ),
    "noteTrusted": MessageLookupByLibrary.simpleMessage(
      "цей комп’ютер довіряє сертифікату",
    ),
    "noteWyrmd": m247,
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
    "openItsTreeNote": m248,
    "openNodeInExplorer": m249,
    "openReplacement": m250,
    "openSettings": MessageLookupByLibrary.simpleMessage("Відкрити параметри"),
    "openingTree": MessageLookupByLibrary.simpleMessage("Відкриваємо дерево"),
    "openingTreeOf": m251,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m252,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "pairsCount": m253,
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
    "paramCount": m254,
    "paramsJson": m255,
    "paramsNotJson": m256,
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
    "pickKeyFull": m257,
    "pickKeyHint": m258,
    "pickKeyOutside": m259,
    "pickKeySelected": MessageLookupByLibrary.simpleMessage(
      "вибрано в Explorer",
    ),
    "pickKeyTyped": m260,
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
    "pickPointHint": MessageLookupByLibrary.simpleMessage(
      "Клацніть точку, щоб побачити її тренд; ⌘/Ctrl-клацання додає до трьох.",
    ),
    "pickPointTrend": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку, щоб побачити її тренд",
    ),
    "pickedFrom": m261,
    "pickedWithStandby": m262,
    "pinField": MessageLookupByLibrary.simpleMessage("Закріпити на блоці"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле лишається на блоці",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Пінг"),
    "planCard": MessageLookupByLibrary.simpleMessage("План"),
    "planChecked": MessageLookupByLibrary.simpleMessage(
      "чекає на схвалення · перевірено",
    ),
    "planCheckedPartly": m263,
    "planNeedsStep": m264,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "План записаний у задачі. Studio покаже його, коли gateway зможе читати документи (docs/studio.md §10 п. 11). Поки що читай план через wyrm-agent.",
    ),
    "planSaved": m265,
    "planSavedSecrets": m266,
    "planSecretNote": MessageLookupByLibrary.simpleMessage(
      "Секретний аргумент не показано. Схвалення все одно стосується значення, яке тримає план.",
    ),
    "planSleep": m267,
    "planSteps": m268,
    "planTimeout": m269,
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
    "pointsCount": m270,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується в пристрій до застосування.",
    ),
    "portBad": MessageLookupByLibrary.simpleMessage("Порт — від 1 до 65535."),
    "portsCount": m271,
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
    "preloadLater": m272,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Читання лінків"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Читання сайтів"),
    "preloadTree": m273,
    "previewInvalid": m274,
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
    "problemNoAnswer": m275,
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
    "problemStudioTooOld": m276,
    "problemUnnamed": MessageLookupByLibrary.simpleMessage("назвіть потік"),
    "problems": MessageLookupByLibrary.simpleMessage("Проблеми"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Очистити все"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Закрити проблеми"),
    "problemsCount": m277,
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
    "qInstalled": m278,
    "qInstalling": m279,
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
    "reachesSites": m280,
    "readAgain": MessageLookupByLibrary.simpleMessage("Прочитати знову"),
    "readFailed": MessageLookupByLibrary.simpleMessage("не прочитано"),
    "readFailedTip": m281,
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
    "refuseNeedsBroker": m282,
    "refuseNoInput": m283,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Вихід не можна зв’язати",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "Блок не може живити сам себе",
    ),
    "refuseType": m284,
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Причина"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "План не виконується. Причина зберігається в записі завдання.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Відхилити план?"),
    "rejectTitle": m285,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Звідси нічого робити: він прийшов разом зі своїм ретранслятором. Відкличте ретранслятор, щоб відрізати його.",
    ),
    "relaysSites": m286,
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
    "removeLinkTitle": m287,
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
    "removeUserTitle": m288,
    "replacedNote": m289,
    "replacedTitle": MessageLookupByLibrary.simpleMessage("замінено"),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultNoValue": MessageLookupByLibrary.simpleMessage("—"),
    "resultNote": MessageLookupByLibrary.simpleMessage(
      "Ключі, яких торкнувся план, з їхніми значеннями зараз.",
    ),
    "resultOf": m290,
    "resultTitle": MessageLookupByLibrary.simpleMessage("Результат"),
    "returns": m291,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "reviewNote": m292,
    "reviewingNote": MessageLookupByLibrary.simpleMessage(
      "Асистент читає, чому виконання зупинилось…",
    ),
    "revision": m293,
    "revisionNow": m294,
    "rightCall": MessageLookupByLibrary.simpleMessage("виклик"),
    "rightMemory": MessageLookupByLibrary.simpleMessage("пам’ять"),
    "rightMib": m295,
    "rightMs": m296,
    "rightNetwork": MessageLookupByLibrary.simpleMessage("мережа"),
    "rightOn": m297,
    "rightStore": MessageLookupByLibrary.simpleMessage("сховище"),
    "rightsLine": m298,
    "rightsNone": MessageLookupByLibrary.simpleMessage("немає"),
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "roleOnSite": m299,
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m300,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Додати рядок"),
    "rowsAnswered": m301,
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
    "rstFile": m302,
    "rstFileNote": m303,
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
    "rstLinkExists": MessageLookupByLibrary.simpleMessage("вже є тут"),
    "rstLinkNew": MessageLookupByLibrary.simpleMessage("новий"),
    "rstLinks": m304,
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
    "rstOtherSite": m305,
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
    "rstReplaceKeys": m306,
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
    "rstRestarting": m307,
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
    "rstTitle": m308,
    "rstUnknown": MessageLookupByLibrary.simpleMessage("Брокер повернувся"),
    "rstUnknownNote": MessageLookupByLibrary.simpleMessage(
      "В аудиті ще немає ні restore_applied, ні restore_failed. Перегляньте Система › Журнал, перш ніж покладатися на відновлення.",
    ),
    "rstUploaded": MessageLookupByLibrary.simpleMessage("Файл на брокері"),
    "rstUploadedNote": MessageLookupByLibrary.simpleMessage(
      "Ще нічого не змінено. Перевірка читає маніфест і порівнює його з цим брокером.",
    ),
    "rstUploading": m309,
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
    "runNowNote": m310,
    "runOff": MessageLookupByLibrary.simpleMessage("Блок вимкнено"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Запускати на кожному старті?",
    ),
    "runPassed": MessageLookupByLibrary.simpleMessage("усі кроки пройшли"),
    "runPassedIn": m311,
    "runPassedLeftOut": m312,
    "runRunning": MessageLookupByLibrary.simpleMessage("виконується…"),
    "runStopped": m313,
    "runStoppedFirst": MessageLookupByLibrary.simpleMessage(
      "зупинено · нічого не змінено",
    ),
    "runStoppedOne": m314,
    "runStopsNote": MessageLookupByLibrary.simpleMessage(
      "зупиняється на першому кроці, що не вдався",
    ),
    "runTitle": m315,
    "runTitleEnded": m316,
    "runWaiting": MessageLookupByLibrary.simpleMessage("чекає"),
    "running": MessageLookupByLibrary.simpleMessage("Працює"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "Агент працює над задачею. Скасування зупиняє її; зроблене лишається.",
    ),
    "runsOn": m317,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
    "saveAsPlan": MessageLookupByLibrary.simpleMessage("Зберегти як план"),
    "savePlanTitle": m318,
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
    "screenOf": m319,
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
    "securityAdded": m320,
    "securityConfirm": MessageLookupByLibrary.simpleMessage(
      "Підтверджувати перед змінами config",
    ),
    "securityConfirmForced": m321,
    "securityConfirmNone": m322,
    "securityDevicesOn": m323,
    "securityDue": m324,
    "securityForget": MessageLookupByLibrary.simpleMessage("Забути"),
    "securityLockAfter": MessageLookupByLibrary.simpleMessage(
      "Блокувати Studio через",
    ),
    "securityLockDesc": m325,
    "securityLockOff": MessageLookupByLibrary.simpleMessage("Вимкнено"),
    "securityMenu": MessageLookupByLibrary.simpleMessage("Безпека"),
    "securityMinutes": m326,
    "securityNoBio": MessageLookupByLibrary.simpleMessage(
      "На цьому комп’ютері немає біометричного відмикання: він питає пароль.",
    ),
    "securityNoDevices": MessageLookupByLibrary.simpleMessage(
      "Пристроїв ще немає.",
    ),
    "securityOn": m327,
    "securityPasswordNeeded": m328,
    "securityPolicy": m329,
    "securityPolicyConfirm": MessageLookupByLibrary.simpleMessage(
      " · підтвердження змін config",
    ),
    "securityPolicyOff": MessageLookupByLibrary.simpleMessage("вимкнено"),
    "securityPolicyOn": MessageLookupByLibrary.simpleMessage("увімкнено"),
    "securityRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "securityRemoved": MessageLookupByLibrary.simpleMessage(
      "видалено · входить лише з паролем",
    ),
    "securityRemovedBy": m330,
    "securitySignOutAll": MessageLookupByLibrary.simpleMessage("Вийти всюди"),
    "securitySignOutAllNote": m331,
    "securitySignedOut": MessageLookupByLibrary.simpleMessage("вийшов"),
    "securityThisDevice": MessageLookupByLibrary.simpleMessage("цей пристрій"),
    "securityTitle": MessageLookupByLibrary.simpleMessage("Безпека"),
    "securityTurnOff": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "securityTurnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "securityUnlockDesc": m332,
    "securityUnlockOffDesc": m333,
    "securityUsedNow": MessageLookupByLibrary.simpleMessage(
      "використано зараз",
    ),
    "seeLinks": MessageLookupByLibrary.simpleMessage("див. Лінки"),
    "seenAgo": m334,
    "seenNow": MessageLookupByLibrary.simpleMessage("зараз"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setLogLevel": m335,
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
    "sitesAround": m336,
    "sitesSubtitle": m337,
    "sizeBytes": m338,
    "sizeChars": m339,
    "sizeColumns": m340,
    "sizeItems": m341,
    "sizeKeys": m342,
    "sizeLines": m343,
    "sizeRows": m344,
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m345,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
    "stagedWas": m346,
    "stale": MessageLookupByLibrary.simpleMessage("застаріле"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Його резервний gateway відповідає на",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "standbyIs": m347,
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
    "stepOf": m348,
    "stepReaching": m349,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Читання вашої ролі та сайтів",
    ),
    "stepSkippedNeeds": m350,
    "stepUpConfirm": MessageLookupByLibrary.simpleMessage("Підтвердити"),
    "stepUpConfirmWith": m351,
    "stepUpDevice": m352,
    "stepUpKeyGone": m353,
    "stepUpLead": m354,
    "stepUpPasswordOnly": m355,
    "stepUpRefused": m356,
    "stepUpStopped": m357,
    "stepUpTitle": MessageLookupByLibrary.simpleMessage(
      "Підтвердіть, що це ви",
    ),
    "stepUpWaiting": m358,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Припинити запис"),
    "stoppedAt": m359,
    "stoppedAtCode": m360,
    "stoppedNote": m361,
    "studioAbout": m362,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "studioVersion": m363,
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
    "sysAttnAcl": m364,
    "sysAttnAclDetail": m365,
    "sysAttnBehind": m366,
    "sysAttnBehindDetail": m367,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag більший за 0: перемикання зараз втратить записи",
    ),
    "sysAttnBroker": m368,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage("Нижчий брокер"),
    "sysAttnBrokerRelays": m369,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysAttnLinkDetail": m370,
    "sysAttnLinkFailed": m371,
    "sysAttnNoStandby": MessageLookupByLibrary.simpleMessage(
      "За цим брокером не слідує резерв",
    ),
    "sysAttnNoStandbyDetail": MessageLookupByLibrary.simpleMessage(
      "standby_connected дорівнює 0",
    ),
    "sysAttnNotRead": m372,
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
    "sysAttnQuarantine": m373,
    "sysAttnQuarantineDetail": m374,
    "sysAttnQuarantineSince": m375,
    "sysBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія та відновлення",
    ),
    "sysBackupNote": m376,
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
    "sysBannerForks": m377,
    "sysBannerLag": m378,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("брокер (усе)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Рівень журналу брокера",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Байти"),
    "sysClear": m379,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Очистити ці від’єднані лінки?",
    ),
    "sysClearAskBody": m380,
    "sysClearBoard": m381,
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
    "sysCleared": m382,
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
    "sysCopyCommand": m383,
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
    "sysGuideCopied": m384,
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
    "sysLinkSource": m385,
    "sysLogCopied": m386,
    "sysLogInvalid": m387,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Потрапляє до «Переглянути й застосувати»; після застосування діє одразу, без перезапуску, і замінює `RUST_LOG`. Zenoh лишається на warn нижче trace. Значення й токени не журналюються нижче trace. Власний рівень лінка: Лінки › лінк › Журнал.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Журнал читають із рівнем config на sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Не вдалося зберегти журнал",
    ),
    "sysLogSaved": m388,
    "sysLogSummary": m389,
    "sysLogSummaryAround": m390,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "sysMetaStarted": m391,
    "sysNeedsLook": m392,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "Зі значень самого брокера. Кожна картка відкриває екран, де це виправляють.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "На цьому рівні рядків немає.",
    ),
    "sysNoLinesAround": m393,
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
    "sysNoStandbyStep2": m394,
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
    "sysNow": m395,
    "sysOfTotal": m396,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Відкрити запис аудиту ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("вихід"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Пакети"),
    "sysProfileFile": m397,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Назва"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m398,
    "sysProfileRemoved": m399,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Профілі пристроїв"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Моделі, які брокер віддає як `pub/<vendor>:<model>`: точки, одиниці та діапазони, що їх успадковують лінки й асистент.",
    ),
    "sysProfilesUnlisted": m400,
    "sysPulled": MessageLookupByLibrary.simpleMessage("забирає щосекунди"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Додати профіль"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Додати профіль…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("записів"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Вилучити"),
    "sysRemoveProfile": m401,
    "sysRemoveProfileAsk": m402,
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
    "sysStaleRow": m403,
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
    "sysSubData": m404,
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
    "sysSubLinkFailed": m405,
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
    "sysSubPeer": m406,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "мережеві сесії; користувачів шлюзу не враховано",
    ),
    "sysSubWaits": m407,
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
    "sysTrafficDescribe": m408,
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
    "tableFiltered": m409,
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
    "tagDownstreamOf": m410,
    "tagNeeds": m411,
    "tagNew": MessageLookupByLibrary.simpleMessage("новий"),
    "tagPlainHttp": MessageLookupByLibrary.simpleMessage("простий http"),
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "tagUsedBefore": MessageLookupByLibrary.simpleMessage("вже використано"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("чекає схвалення"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "чекає на твою відповідь",
    ),
    "taskBy": m412,
    "taskDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "taskFailed": MessageLookupByLibrary.simpleMessage(
      "не вдалося або зупинено",
    ),
    "taskFailedAt": m413,
    "taskListNote": m414,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("нічого не змінено"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("планує"),
    "taskReplaced": m415,
    "taskRunning": MessageLookupByLibrary.simpleMessage("виконує"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "thisNetwork": MessageLookupByLibrary.simpleMessage("цій мережі"),
    "timelineAudit": MessageLookupByLibrary.simpleMessage("З sys/audit"),
    "timelineAuditLine": m416,
    "timelineAuditNone": MessageLookupByLibrary.simpleMessage(
      "Немає змін цієї точки в останніх 500 записах sys/audit.",
    ),
    "timelineLabel": m417,
    "tlsCertificateOf": m418,
    "tlsNotTrusted": m419,
    "tlsPinned": m420,
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Закрити"),
    "toastHidesIn": m421,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Сповіщення"),
    "toastStays": m422,
    "toastStream": MessageLookupByLibrary.simpleMessage(
      "Studio відкриє потоки знову, коли він повернеться.",
    ),
    "todayUsed": m423,
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
    "treeOf": m424,
    "treePoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "на блоці: додає її як поле. На полотні: новий блок цього вузла.",
    ),
    "treePointNote2": MessageLookupByLibrary.simpleMessage(
      "на полотні: блок, що її читає (записувана точка питає «Читати» чи «Писати»; Alt пише). На полі: прив\'язується до нього.",
    ),
    "trendAll": MessageLookupByLibrary.simpleMessage("усе"),
    "trendAllHidden": MessageLookupByLibrary.simpleMessage("Усі ряди сховано."),
    "trendAvg": m425,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "записано погану якість",
    ),
    "trendBucket": m426,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть A ще раз, щоб прибрати її",
    ),
    "trendDelta": m427,
    "trendDescribe": m428,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("До поточного часу"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Наведіть для значень · тягніть по графіку, щоб наблизити · клацніть, щоб поставити мітку A · тягніть або змінюйте вікно внизу · подвійне клацання скидає · ← → рухають вибрану ручку",
    ),
    "trendHoursMinutes": m429,
    "trendLocked": m430,
    "trendMarker": m431,
    "trendMinMax": m432,
    "trendMinutes": m433,
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
    "trendPoint": m434,
    "trendRaw": MessageLookupByLibrary.simpleMessage("сирі"),
    "trendRawAt": m435,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Скинути масштаб"),
    "trendSeconds": m436,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть, щоб поставити мітку A",
    ),
    "trendShowHide": m437,
    "trendStepDays": m438,
    "trendStepHours": m439,
    "trendStepMinutes": m440,
    "trendUncertain": MessageLookupByLibrary.simpleMessage(
      "uncertain · застарілі читання в цьому інтервалі",
    ),
    "trendWeekdays": MessageLookupByLibrary.simpleMessage(
      "Пн,Вт,Ср,Чт,Пт,Сб,Нд",
    ),
    "trendWindowEnd": MessageLookupByLibrary.simpleMessage("Кінець вікна"),
    "trendWindowStart": MessageLookupByLibrary.simpleMessage("Початок вікна"),
    "trustCode": MessageLookupByLibrary.simpleMessage("Код CA"),
    "trustMatches": m441,
    "trustRefusedChain": m442,
    "trustRefusedChanged": MessageLookupByLibrary.simpleMessage(
      "Gateway тепер надсилає інший CA, ніж показано. Нічому не довірено.",
    ),
    "trustRefusedMismatch": MessageLookupByLibrary.simpleMessage(
      "Код, який заявляє gateway, не є кодом його CA. Нічому не довірено.",
    ),
    "trustRefusedNoAnswer": MessageLookupByLibrary.simpleMessage(
      "Gateway не відповів удруге. Нічому не довірено.",
    ),
    "trustTitle": m443,
    "trustWhere": m444,
    "trustWhy": m445,
    "tryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "typeOrFind": MessageLookupByLibrary.simpleMessage(
      "Введіть адресу або знайдіть її в цій мережі.",
    ),
    "unbind": MessageLookupByLibrary.simpleMessage("Розв’язати"),
    "unitNumber": m446,
    "unlockAgoNow": MessageLookupByLibrary.simpleMessage("зараз"),
    "unlockAnother": MessageLookupByLibrary.simpleMessage(
      "Інший обліковий запис або шлюз",
    ),
    "unlockCancelTitle": m447,
    "unlockChangedFaces": m448,
    "unlockChangedFingers": m449,
    "unlockChangedTitle": m450,
    "unlockChecking": m451,
    "unlockConfirmPrompt": m452,
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
    "unlockDueText": m453,
    "unlockDueTitle": m454,
    "unlockEnablePrompt": m455,
    "unlockFactEndsFaces": MessageLookupByLibrary.simpleMessage(
      "Він перестає діяти, коли тут змінюються обличчя, коли змінюється ваш пароль або коли адміністратор видаляє цей пристрій.",
    ),
    "unlockFactEndsFingers": MessageLookupByLibrary.simpleMessage(
      "Він перестає діяти, коли тут змінюються відбитки пальців, коли змінюється ваш пароль або коли адміністратор видаляє цей пристрій.",
    ),
    "unlockFactPassword": m456,
    "unlockFactSite": m457,
    "unlockFactStandby": m458,
    "unlockFactStore": m459,
    "unlockFallbackText": m460,
    "unlockKeyIn": m461,
    "unlockLastPassword": MessageLookupByLibrary.simpleMessage("пароль"),
    "unlockLastUsed": m462,
    "unlockLockoutTitle": m463,
    "unlockLogInTo": m464,
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
    "unlockOffTitle": m465,
    "unlockOffToast": m466,
    "unlockOfferChecked": m467,
    "unlockOfferText": m468,
    "unlockOfferTitle": m469,
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
    "unlockPasswordFor": m470,
    "unlockPlusStandby": m471,
    "unlockPolicyLine": m472,
    "unlockPrompt": m473,
    "unlockReEnable": m474,
    "unlockRemovedText": m475,
    "unlockRemovedTitle": MessageLookupByLibrary.simpleMessage(
      "Видалено адміністратором",
    ),
    "unlockRoleOn": m476,
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
    "unlockToOpen": m477,
    "unlockUnknownText": m478,
    "unlockUnknownTitle": m479,
    "unlockUse": m480,
    "unlockUsePassword": MessageLookupByLibrary.simpleMessage(
      "Увійти з паролем",
    ),
    "unlockWelcomeBack": MessageLookupByLibrary.simpleMessage("З поверненням"),
    "unlockWith": m481,
    "unpinField": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "Брокер, можливо, перезапускається, або цей комп’ютер в іншій мережі.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "Точка більше не записується; рядки лишаються.",
    ),
    "upFor": m482,
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
    "updDo": m483,
    "updFailed": m484,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "Перевірка стану закінчилась без відповіді від кожного лінка.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("Новіший архів"),
    "updFromFileNote": m485,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Оновити з файлу…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("зникли"),
    "updHotStart": m486,
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
    "updKeptUntil": m487,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "Можна піти з цього екрана; оновлення триває.",
    ),
    "updLinksCount": m488,
    "updLinksRestart": m489,
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
    "updOpenLink": m490,
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
    "updPointBeforeRestore": m491,
    "updPointBeforeUpdate": m492,
    "updPoints": MessageLookupByLibrary.simpleMessage("Точки відновлення"),
    "updRights": MessageLookupByLibrary.simpleMessage("Права і мережа"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "Якщо нова версія просить більше, ніж мають лінки, брокер нічого не встановлює і показує перелік тут для прийняття.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Відкотити"),
    "updRollBackNote": m493,
    "updRollBackTitle": m494,
    "updRollBackTo": m495,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "Лінки знову працюють на збереженій версії.",
    ),
    "updRolledBackTo": m496,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("перевіряється"),
    "updRuns": m497,
    "updRunsNote": m498,
    "updStateChanges": m499,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "Стара версія не читає нове сховище: відкат відновлює сховище з точки відновлення.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Формат сховища: каже архів",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "Якщо архів не читає встановлений формат сховища, брокер відмовляє в оновленні без точки відновлення.",
    ),
    "updStateSame": m500,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "Нова версія читає сховище встановленої.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Стан: кожен лінк повернувся зі своїми вузлами",
    ),
    "updStepNodesCount": m501,
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
    "updSubCustom": m502,
    "updSubOfficial": m503,
    "updTab": MessageLookupByLibrary.simpleMessage("Оновлення"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Лінки, пакет яких має новішу версію. Усі лінки пакета оновлюються разом, і брокер зберігає потрібне для повернення.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Потім"),
    "updTitle": m504,
    "updTitleCustom": m505,
    "updTitleDone": m506,
    "updTitleRolledBack": m507,
    "updTogether": MessageLookupByLibrary.simpleMessage("оновлюються разом"),
    "updUnknownResult": m508,
    "updUnknownResultNote": MessageLookupByLibrary.simpleMessage(
      "Studio не знає такого результату. Більше скаже журнал брокера.",
    ),
    "updUpdating": m509,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Оновлення…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Значення його лінків зупиняються на час перезапуску.",
    ),
    "updVersionsOf": m510,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "Що змінюється для брокера",
    ),
    "updWhatIsNew": m511,
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
    "versionDeployed": m512,
    "viaSite": m513,
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
    "viewerCsvRules": m514,
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
    "viewerSaveHint": m515,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("Як таблиця"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Текст"),
    "viewerTableHint": m516,
    "waitNotRead": MessageLookupByLibrary.simpleMessage(
      "ця Studio не прочитала",
    ),
    "waitNotReadNote": MessageLookupByLibrary.simpleMessage(
      "Відповідь у формі, якої ця Studio не читає; вирішуй на брокері. Дивись Проблеми.",
    ),
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "waitingToBeLetIn": m517,
    "wasValue": m518,
    "wasWord": MessageLookupByLibrary.simpleMessage("було"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Група спостереження"),
    "watchGroups": m519,
    "waysCaution": m520,
    "waysNote": MessageLookupByLibrary.simpleMessage(
      "Вибір — це нове прохання. Його план перевіряють, і він чекає на ваше схвалення крок за кроком.",
    ),
    "waysOut": MessageLookupByLibrary.simpleMessage("Що далі"),
    "welcomeUser": m521,
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
    "whyNotRead": MessageLookupByLibrary.simpleMessage("не прочитано"),
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
    "wouldRun": m522,
    "wouldSend": m523,
    "wouldWrite": m524,
    "writableNeeds": m525,
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
    "wyrmdOn": m526,
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
