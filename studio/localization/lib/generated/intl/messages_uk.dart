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

  static String m3(n) => "${n} д тому";

  static String m4(n) => "${n} год тому";

  static String m5(n) => "${n} хв тому";

  static String m6(count) =>
      "${Intl.plural(count, one: 'Застосувати 1 зміну', few: 'Застосувати ${count} зміни', other: 'Застосувати ${count} змін')}";

  static String m7(n) =>
      "${Intl.plural(n, one: 'Схвалити 1 зміну й запустити', few: 'Схвалити ${n} зміни й запустити', other: 'Схвалити ${n} змін і запустити')}";

  static String m8(site) =>
      "Це завдання на сайті ${site}. Цей шлюз підписує схвалення лише для завдань власного сайту. Схваліть його через шлюз сайту ${site}.";

  static String m9(why) => "Схвалення відхилено; завдання ще чекає. ${why}";

  static String m10(role) =>
      "Підписує один токен на кожен позначений крок з вашими правами (${role}). Непозначені кроки пропускаються.";

  static String m11(count) => "Попросити адміністратора: ${count}";

  static String m12(n) => "просить приєднатися · ретранслює ${n}";

  static String m13(sites) => "просить ретранслювати: ${sites}";

  static String m14(code) => "відмовлено (${code})";

  static String m15(id) =>
      "Лінк ${id} уже є на цьому брокері: його буде замінено на місці (той самий драйвер і режим), спершу створюється його точка відновлення.";

  static String m16(size, rights) => "Близько ${size} · ${rights}";

  static String m17(days) =>
      "Створюються під час роботи брокера і зберігаються на ньому ${days} днів. Завантажте копію або надішліть у файлове сховище.";

  static String m18(name) => "Виберіть теку для ${name}";

  static String m19(link) => "Створити копію ${link}";

  static String m20(when) =>
      "Зберігається на брокері до ${when} (резервні копії).";

  static String m21(done, size) => "Завантаження: ${done} з ${size}";

  static String m22(what) => "Копію ${what} не створено";

  static String m23(site) =>
      "У ній ключі сайту: хто має файл і парольну фразу, той адміністратор ${site}.";

  static String m24(link) => "лінк ${link}";

  static String m25(n) => "Щонайменше ${n} символів";

  static String m26(what) => "Створення копії ${what}";

  static String m27(name) => "Видалити ${name}?";

  static String m28(percent) => "створюється · ${percent} %";

  static String m29(percent) => "надсилається · ${percent} %";

  static String m30(name) => "Збережено ${name}";

  static String m31(size, n) => "${size} · секцій: ${n}";

  static String m32(path) => "Збережено до ${path}; SHA-256 перевірено.";

  static String m33(site) =>
      "запечатано для ${site}: відкривається лише на брокері з його ключами";

  static String m34(error) => "Не надіслано: ${error}";

  static String m35(to) => "Надсилання до ${to}";

  static String m36(link) =>
      "Один файл .wyrm-link з усім, що потрібно ${link} для повернення тут або на іншому брокері.";

  static String m37(site) => "Резервна копія ${site}";

  static String m38(link) => "Резервна копія лінка ${link}";

  static String m39(days) => "Зберігається в резервних копіях ${days} днів.";

  static String m40(days) =>
      "Завантажується частинами, коли готова; також зберігається на брокері ${days} днів.";

  static String m41(n) =>
      "${Intl.plural(n, one: '${n} блок', few: '${n} блоки', other: '${n} блоків')}";

  static String m42(brokers, devices) =>
      "${brokers} брокерів · ${devices} пристроїв";

  static String m43(driver) => "вбудований драйвер ${driver}";

  static String m44(version) => "Знову на ${version}";

  static String m45(tried, version) =>
      "${tried} не пройшла пробний старт. Наступний старт повернув ${version} і відновив площину керування з копії перед оновленням.";

  static String m46(version, latest) => "${version} · доступна ${latest}";

  static String m47(version) => "${version} · актуальна";

  static String m48(version) => "${version} · оновлення відкочено";

  static String m49(version) => "${version} на випробуванні";

  static String m50(version) =>
      "Якщо нова версія записує новішу SCHEMA, ${version} потім її не прочитає: відкат відновлює копію площини керування, зроблену перед оновленням, тож зміни після оновлення втрачаються.";

  static String m51(from, to) => "Зупинено на ${from}, запущено на ${to}";

  static String m52(version) => "${version} підготовлено";

  static String m53(back, all, seconds) => "${back} з ${all} за ${seconds} с";

  static String m54(time) =>
      "Studio втратила шлюз і пробує знову самостійно · ${time}";

  static String m55(version) => "Відкрити журнал ${version}";

  static String m56(site, version) => "${site} перезапускається на ${version}";

  static String m57(site, version) => "Відкотити ${site} до ${version}?";

  static String m58(when) => "можливий до ${when}";

  static String m59(site, version) => "${site} працює на ${version}";

  static String m60(version) =>
      "Оновлення підтверджено; ${version} і копія перед оновленням зберігаються для відкату.";

  static String m61(n) => "${n} с";

  static String m62(version) =>
      "Новий бінарник розміщується поруч із поточним; ${version} залишається на диску.";

  static String m63(version) =>
      "Брокер чисто зупиняється, і менеджер служб запускає ${version} (приблизно 5–15 с без брокера).";

  static String m64(version) =>
      "${version} працює на випробуванні: за 3 хв мають повернутися роутер, шлюз і його лінки.";

  static String m65(version) =>
      "Потім він підтверджує себе. Якщо ні, наступний старт повертає ${version} з копією з кроку 1.";

  static String m66(site, version) => "Оновити ${site} до wyrmd ${version}";

  static String m67(site) => "Введіть ${site} для підтвердження";

  static String m68(site) => "${site} оновлено";

  static String m69(site) => "Оновлення ${site}";

  static String m70(site) => "підписано CA · ${site} CA";

  static String m71(n) =>
      "${Intl.plural(n, one: '1 блок стає', few: '${n} блоки стають', other: '${n} блоків стають')} одним блоком цього флоу. Дроти, що перетинають його межу, стають його входами та виходами.";

  static String m72(count) =>
      "${Intl.plural(count, zero: 'без дочірніх вузлів', one: '${count} дочірній вузол', few: '${count} дочірні вузли', other: '${count} дочірніх вузлів')}";

  static String m73(site) =>
      "${site} під’єднується до нього; там авторизують ${site}.";

  static String m74(size) => "data_dir ${size}";

  static String m75(id) => "Відкликати допуск ${id}?";

  static String m76(flow) =>
      "Чернетка «${flow}» замінить версію, що працює зараз.";

  static String m77(who) => "розгорнув ${who}";

  static String m78(steps) =>
      "Завдання виконано. Пропущені кроки: ${steps}. Попросіть їх окремим завданням; його план схвалюють окремо.";

  static String m79(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m80(id) => "Параметри ${id}";

  static String m81(time) =>
      "Решта подробиць у журналі брокера близько ${time}.";

  static String m82(field) =>
      "У формі поле ${field} позначено; виправте його та надішліть знову.";

  static String m83(role, site) =>
      "Ваша роль: ${role}. На ${site} нічого не змінено.";

  static String m84(call, key) => "${call} на ${key}";

  static String m85(type) => "studio · ${type}";

  static String m86(thing) => "розгорнути ${thing}";

  static String m87(thing) => "встановити ${thing}";

  static String m88(thing) => "отримати список ${thing}";

  static String m89(thing) => "увійти до ${thing}";

  static String m90(thing) => "відкрити ${thing}";

  static String m91(thing) => "прочитати ${thing}";

  static String m92(thing) => "вилучити ${thing}";

  static String m93(call, thing) => "виконати ${call} на ${thing}";

  static String m94(thing) => "зберегти ${thing}";

  static String m95(thing) => "запустити ${thing}";

  static String m96(step) => "завершити «${step}»";

  static String m97(thing) => "зупинити ${thing}";

  static String m98(thing) => "записати ${thing}";

  static String m99(thing) => "Розгортання ${thing}";

  static String m100(thing) => "Встановлення ${thing}";

  static String m101(thing) => "Список ${thing}";

  static String m102(thing) => "Вхід до ${thing}";

  static String m103(thing) => "Відкриття ${thing}";

  static String m104(thing) => "Читання ${thing}";

  static String m105(thing) => "Вилучення ${thing}";

  static String m106(call, thing) => "${call} на ${thing}";

  static String m107(thing) => "Збереження ${thing}";

  static String m108(thing) => "Запуск ${thing}";

  static String m109(thing) => "Зупинка ${thing}";

  static String m110(thing) => "Запис ${thing}";

  static String m111(call) => "${call}";

  static String m112(site) => "Брокер на ${site} не відповів.";

  static String m113(status) => "Брокер відповів ${status} без повідомлення.";

  static String m114(status, message) => "${status}: ${message}";

  static String m115(time) => "${time} (місцевий)";

  static String m116(doing, site) => "${doing}: помилка на ${site}";

  static String m117(doing) => "${doing}: помилка";

  static String m118(site, what) => "${site} зайнятий: ${what} не почато";

  static String m119(thing) => "${thing} більше немає";

  static String m120(thing) => "Історія ${thing} недоступна";

  static String m121(site) => "${site} не відповідає";

  static String m122(thing) => "Не вдалося прочитати ${thing}";

  static String m123(what) => "Ви не можете ${what}";

  static String m124(site) => "Живі значення з ${site} зупинилися";

  static String m125(what) => "Studio не вдалося ${what}";

  static String m126(thing, call) => "${thing} не підтримує ${call}";

  static String m127(seconds) => "Ще раз через ${seconds} с";

  static String m128(user, role) => "${user} (${role})";

  static String m129(s) => "кожні ${s} с";

  static String m130(reason) =>
      "Нечитаний файл не вдалося відкласти: ${reason}";

  static String m131(name) =>
      "Нечитаний файл лишиться поруч із новим як ${name}. Ви знову додасте свої gateway та увійдете.";

  static String m132(panel) => "Studio не вдалося намалювати: ${panel}";

  static String m133(panel) => "Не вдалося намалювати: ${panel}";

  static String m134(when) => "уперше ${when}";

  static String m135(v) => "v${v} розгорнуто";

  static String m136(v) => "v${v} · помилка";

  static String m137(v) => "v${v} зупинено";

  static String m138(v) => "Версія ${v}";

  static String m139(site) => "Потоки на ${site}";

  static String m140(count) => "Блоків: ${count}";

  static String m141(label) => "Відкріпити «${label}» від блока";

  static String m142(task, steps) =>
      "Виконай кроки, пропущені в плані завдання ${task}: ${steps}.";

  static String m143(address) => "з ${address}";

  static String m144(host, ms) => "${host} · відповів за ${ms} мс";

  static String m145(host) => "Немає відповіді від ${host}";

  static String m146(key) => "Перейти до ${key}";

  static String m147(id) => "Доступ для ${id}";

  static String m148(days) => "сирі дані ${days} д";

  static String m149(n) => "${n} рядів";

  static String m150(size) => "Історик ${size}";

  static String m151(id) => "Історія параметрів ${id}";

  static String m152(status) =>
      "Не вдалося прочитати історію: ${status}. Подробиці в «Проблемах».";

  static String m153(n) =>
      "${Intl.plural(n, one: '1 вхід', few: '${n} входи', other: '${n} входів')}";

  static String m154(name, broker) => "${name} встановлено на ${broker}.";

  static String m155(n) =>
      "${Intl.plural(n, zero: 'у цьому флоу немає екземплярів', one: '1 екземпляр у цьому флоу', few: '${n} екземпляри в цьому флоу', other: '${n} екземплярів у цьому флоу')} · зміна тут змінює всі";

  static String m156(count) => "Скопійовано ключів: ${count}";

  static String m157(lag) => "відставання ${lag}";

  static String m158(time) => "останнє читання ${time}";

  static String m159(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m160(n) =>
      "${Intl.plural(n, one: '${n} лінк', few: '${n} лінки', other: '${n} лінків')}";

  static String m161(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m162(site) => "Лінки на ${site}";

  static String m163(first, last) => "${first} і ${last}";

  static String m164(status) =>
      "Не вдалося прочитати список дочірніх вузлів: ${status}. Подробиці в «Проблемах».";

  static String m165(id) => "Журнал ${id}";

  static String m166(n) =>
      "${Intl.plural(n, one: 'його вживає 1 екземпляр', few: 'його вживають ${n} екземпляри', other: 'його вживають ${n} екземплярів')}";

  static String m167(n) => "бібліотека v${n}";

  static String m168(n) => "вжито: ${n}";

  static String m169(n) => "v${n}";

  static String m170(kind, count) => "${kind} · дій: ${count}";

  static String m171(status) =>
      "Не вдалося прочитати опис: ${status}. Подробиці в «Проблемах».";

  static String m172(count) =>
      "${Intl.plural(count, one: '… ще ${count} байт', few: '… ще ${count} байти', other: '… ще ${count} байтів')}";

  static String m173(count) =>
      "${Intl.plural(count, one: 'ще ${count} рядок', few: 'ще ${count} рядки', other: 'ще ${count} рядків')}";

  static String m174(count) => "Вибрано: ${count}";

  static String m175(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m176(level) => "Потрібно ${level} · у вас є";

  static String m177(action) => "Цей вузол не має дії ${action}.";

  static String m178(param) => "Драйвер не має параметра ${param}.";

  static String m179(site) => "немає: ${site} — вершина";

  static String m180(site) => "Дерево покаже wy/${site}.";

  static String m181(site) => "Відкриваємо дерево сайту ${site}…";

  static String m182(name) => "пакет ${name}";

  static String m183(n) =>
      "${Intl.plural(n, one: '1 випадок', few: '${n} випадки', other: '${n} випадків')}";

  static String m184(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m185(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m186(detail) => "Це не JSON: ${detail}";

  static String m187(n) => "потребує кроку ${n}";

  static String m188(s) => "${s} с";

  static String m189(n) => "План · кроків: ${n}";

  static String m190(s) => "тайм-аут ${s} с";

  static String m191(n) =>
      "${Intl.plural(n, one: '${n} точка', few: '${n} точки', other: '${n} точок')}";

  static String m192(n) =>
      "${Intl.plural(n, one: '1 порт', few: '${n} порти', other: '${n} портів')}";

  static String m193(step) => "${step} · пізніше";

  static String m194(site) => "Читання дерева сайту ${site}";

  static String m195(message) => "Чернетка не запускається: ${message}";

  static String m196(count) =>
      "${Intl.plural(count, one: '1 проблема', few: '${count} проблеми', many: '${count} проблем', other: '${count} проблеми')}";

  static String m197(name) => "${name} встановлено";

  static String m198(name) => "Встановлення ${name}…";

  static String m199(sites) => "досягає ${sites}";

  static String m200(status) =>
      "Не вдалося прочитати значення: ${status}. Подробиці в «Проблемах».";

  static String m201(field) =>
      "Цей брокер не може прив\'язати ${field} (його рушій флоу старший за ADR 0040)";

  static String m202(field) => "${field} не має входу: введіть значення";

  static String m203(from, to) => "${from} не підходить до ${to}";

  static String m204(cn) => "Відхилити ${cn}?";

  static String m205(n) =>
      "${Intl.plural(n, one: 'ретранслює ${n} сайт', few: 'ретранслює ${n} сайти', other: 'ретранслює ${n} сайтів')}";

  static String m206(id) => "Видалити ${id}?";

  static String m207(name) => "Видалити ${name}?";

  static String m208(action) => "Результат · ${action}";

  static String m209(what) => "повертає ${what}";

  static String m210(audit) =>
      "Кожен запис перевіряє лінк і фіксує в ${audit}. Значення зʼявляється лише після зворотного читання.";

  static String m211(rev) => "Ревізія ${rev}";

  static String m212(rev) => "Ревізія ${rev} · діє";

  static String m213(site, user, role, level) =>
      "Сайт ${site} · застосовується з вашими правами: ${user}, ${role} (${level})";

  static String m214(role, site) => "${role} на ${site}";

  static String m215(rev) => "Повернути ревізію ${rev}?";

  static String m216(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m217(site, broker) => "З ${site} · wyrmd ${broker}";

  static String m218(when, n, sealed) =>
      "Створено ${when} · секцій: ${n} · секрети: ${sealed}";

  static String m219(fresh, exists) =>
      "Лінки: нових ${fresh}, наявних тут ${exists}";

  static String m220(site) => "Копія іншого сайту: ${site}";

  static String m221(files) => "Замінити ключі сайту: ${files}";

  static String m222(site) => "${site} перезапускається і застосовує копію";

  static String m223(site) => "Відновити ${site} з резервної копії";

  static String m224(done, size) => "Вивантаження: ${done} з ${size}";

  static String m225(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m226(site) => "Працює на ${site}";

  static String m227(name) => "${name}";

  static String m228(level) => "Рівень журналу ${level}";

  static String m229(site) => "Сайти навколо ${site}";

  static String m230(site) =>
      "До чого під’єднаний ${site} і що під’єднано до нього: брокери вище й нижче, платформи, куди він надсилає, і пристрої, чиї лінки працюють поза брокером.";

  static String m231(count) =>
      "${Intl.plural(count, one: '${count} байт', few: '${count} байти', other: '${count} байтів')}";

  static String m232(count) =>
      "${Intl.plural(count, one: '${count} символ', few: '${count} символи', other: '${count} символів')}";

  static String m233(count) =>
      "${Intl.plural(count, one: '${count} стовпець', few: '${count} стовпці', other: '${count} стовпців')}";

  static String m234(count) =>
      "${Intl.plural(count, one: '${count} елемент', few: '${count} елементи', other: '${count} елементів')}";

  static String m235(count) =>
      "${Intl.plural(count, one: '${count} ключ', few: '${count} ключі', other: '${count} ключів')}";

  static String m236(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m237(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m238(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m239(was) => "підготовлено · було ${was}";

  static String m240(host) => "Резерв: ${host}";

  static String m241(n, total) => "Крок ${n} з ${total}";

  static String m242(host) => "З’єднання з ${host}";

  static String m243(n) => "пропущено: потрібен крок ${n}";

  static String m244(version, os) => "${version} (${os})";

  static String m245(version, language) => "Studio ${version} · ${language}";

  static String m246(n) => "Відмов ACL побільшало на ${n}";

  static String m247(from) =>
      "acl_denied дорівнював ${from}, коли цей екран показували востаннє";

  static String m248(n) => "Резерв відстає на ${n} записів";

  static String m249(n) => "Відкладено розгалужень після розколу: ${n}";

  static String m250(site) => "${site} чекає на Authorize";

  static String m251(n) => "Нижчий брокер, що ретранслює сайтів: ${n}";

  static String m252(id) =>
      "sys/links/${id}/state має стан failed; причина в його журналі";

  static String m253(id) => "${id} не працює";

  static String m254(cn) => "${cn} чекає в карантині";

  static String m255(cn) => "Невідомий сертифікат CN ${cn}";

  static String m256(cn, t) => "Невідомий сертифікат CN ${cn} від ${t}";

  static String m257(size) =>
      "Усе, чим володіє брокер, лежить у його `data_dir` (тут ${size}). Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:";

  static String m258(n) =>
      "Наборів записів, відкладених після того, як обидва брокери були активні (усунений розкол): ${n}. Запис аудиту `standby_forked` каже які.";

  static String m259(n) =>
      "Записів реєстру, яких ще немає на резерві: ${n}. Перемикання зараз їх втратить.";

  static String m260(n) => "Очистити від’єднані лінки (${n})…";

  static String m261(ids) =>
      "${ids}\n\nЇхні id вибувають і більше не можуть бути використані.";

  static String m262(n) => "Очистити від’єднані лінки: ${n}…";

  static String m263(ids) => "Вилучено: ${ids}";

  static String m264(title) => "Копіювати: ${title}";

  static String m265(url) => "Посилання на посібник скопійовано: ${url}";

  static String m266(id) => "лінк: ${id}";

  static String m267(n) => "Скопійовано рядків: ${n}";

  static String m268(path) => "Збережено ${path}";

  static String m269(n) =>
      "Рядків із кільця брокера: ${n} · новіші зверху · `sys/~act/get_log`";

  static String m270(n, m, time) =>
      "Рядків у межах 2 хв від ${time} UTC: ${n} з ${m} · новіші зверху · `sys/~act/get_log`";

  static String m271(t) => "запущено ${t}";

  static String m272(n) => "Потребує уваги · ${n}";

  static String m273(m, time) =>
      "Серед найновіших ${m} рядків немає жодного в межах 2 хв від ${time} UTC. Запитайте більше рядків або очистьте час.";

  static String m274(standby) =>
      "2. У `wyrmd.json5` на обох хостах: `${standby}` і `peers.listen`; радимо `arbiter` оренди на третьому хості.";

  static String m275(t) => "${t} · зараз";

  static String m276(n) => "з ${n}";

  static String m277(name) =>
      "Файл ${name}. Файл .cbor надсилається як є; файл JSON спершу кодується.";

  static String m278(name) => "Профіль ${name} додано";

  static String m279(name) => "Профіль ${name} вилучено";

  static String m280(reason) =>
      "Цей брокер не віддає перелік профілів через шлюз (${reason}). Профіль усе одно можна додати; брокер віддаватиме його як pub/<name>.";

  static String m281(name) => "Вилучити профіль ${name}";

  static String m282(name) =>
      "Брокер перестає віддавати pub/${name} і записує це в журнал аудиту (profile_remove).";

  static String m283(cn) => "зовнішній · CN ${cn}";

  static String m284(size) => "історія ${size} · відкрити Історію";

  static String m285(id) => "${id} не працює · відкрити Лінки";

  static String m286(site) => "${site} · відкрити Сайти";

  static String m287(cn) => "${cn} чекає · відкрити Карантин";

  static String m288(measure, from, to) =>
      "${measure} на вхід і вихід за секунду від ${from} до ${to}";

  static String m289(shown, total) => "${shown} з ${total} рядків";

  static String m290(level) => "потрібно ${level}";

  static String m291(who) => "від ${who}";

  static String m292(n) => "помилка на кроці ${n}";

  static String m293(agent) => "Кожна задача — вузол: ${agent}/tasks/<id>";

  static String m294(site) => "TLS · сертифікат CA сайту ${site}";

  static String m295(seconds) => "зникне через ${seconds} с";

  static String m296(site) => "лишається, доки ${site} не повернеться";

  static String m297(site) => "Дерево · ${site}";

  static String m298(step) => "середнє за ${step}";

  static String m299(rollup, from, to) => "${rollup} · ${from}–${to}";

  static String m300(at, delta, key, over) =>
      "Δ від A (${at}): ${delta} ${key} за ${over}";

  static String m301(what, range) =>
      "${what}, ${range}. Виберіть діапазон вікном нижче.";

  static String m302(h, m) => "${h} год ${m} хв";

  static String m303(key) => "Ви не можете читати ${key}";

  static String m304(t) => "A · ${t}";

  static String m305(min, max) => "мін ${min} · макс ${max}";

  static String m306(m) => "${m} хв";

  static String m307(t) => "сирі · ${t}";

  static String m308(s) => "${s} с";

  static String m309(name) => "Показати або сховати ${name}";

  static String m310(n) => "${n} д";

  static String m311(n) => "${n} год";

  static String m312(n) => "${n} хв";

  static String m313(unit) => "адреса ${unit}";

  static String m314(d) => "працює ${d}";

  static String m315(n) => "Оновити лінків: ${n}";

  static String m316(version) => "${version} залишається, лінк не відповів";

  static String m317(package) =>
      "Дайте zip пакета ${package} з вищою версією. Брокер перевіряє його як будь-яке встановлення і оновлює всі лінки пакета.";

  static String m318(links) => "Гарячий старт, без перезапуску: ${links}";

  static String m319(version, when) =>
      "${version} залишається встановленою до ${when}. Точка відновлення запечатана для цього брокера і залишається на ньому.";

  static String m320(n) => "лінків: ${n}";

  static String m321(n, links) => "Лінки, що перезапускаються (${n}): ${links}";

  static String m322(link) => "Відкрити ${link}";

  static String m323(link) => "${link} · перед відновленням з резервної копії";

  static String m324(link, version) =>
      "${link} · ${version} · перед оновленням";

  static String m325(version, links) =>
      "Ці лінки зупиняться і запустяться на ${version}: ${links}. Брокер повертає їхні приватні дані до точки відновлення оновлення, якщо оновлення змінило формат сховища або закінчилося погано; після вдалого оновлення вони зберігають поточні дані. Після цього жодна версія не зберігається: другого відкату немає.";

  static String m326(package, version) => "Відкотити ${package} до ${version}?";

  static String m327(version) => "Відкотити до ${version}…";

  static String m328(version) => "Відкочено до ${version}";

  static String m329(version) => "Лінки працюють на ${version}";

  static String m330(links) => "${links}: повернулися з усіма вузлами.";

  static String m331(state) => "Він змінює формат сховища (зі state ${state})";

  static String m332(state) => "Формат сховища: той самий (state ${state})";

  static String m333(back, gone) =>
      "оголошено знову: ${back} · ще немає або зникло: ${gone}";

  static String m334(n) => "Власний пакет · лінків на ньому: ${n}";

  static String m335(n) => "Пакет репозиторію · лінків на ньому: ${n}";

  static String m336(package, from, to) => "Оновити ${package} ${from} → ${to}";

  static String m337(package, from) => "Оновити ${package} ${from} з файлу";

  static String m338(package) => "${package} оновлено";

  static String m339(package) => "Оновлення ${package} відкочено";

  static String m340(package) => "Оновлення ${package}";

  static String m341(package) => "Версії ${package}";

  static String m342(version) => "Що нового у ${version}";

  static String m343(v) => "Версія ${v} · розгорнута";

  static String m344(site) => "через ${site}";

  static String m345(delimiter, header) =>
      "Так, як його читає блок: роздільник ${delimiter}, ${header}";

  static String m346(keys) => "${keys} зберігає · Esc скасовує";

  static String m347(keys) => "${keys} зберігає · Esc відкидає зміни";

  static String m348(n, who) => "${n} чекають на допуск: ${who}";

  static String m349(value) => "було ${value}";

  static String m350(n) => "Групи спостереження · ${n}";

  static String m351(user) => "Вітаємо, ${user}";

  static String m352(value) => "запустив би на ${value}";

  static String m353(value) => "надіслав би ${value}";

  static String m354(value) => "записав би ${value}";

  static String m355(level) => "Щоб увімкнути, потрібен рівень ${level}";

  static String m356(site) => "wyrmd на ${site}";

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
    "addGrant": MessageLookupByLibrary.simpleMessage("Додати дозвіл"),
    "addInput": MessageLookupByLibrary.simpleMessage("Додати вхід"),
    "addPair": MessageLookupByLibrary.simpleMessage("Додати випадок"),
    "addPoint": MessageLookupByLibrary.simpleMessage("Додати точку"),
    "addPort": MessageLookupByLibrary.simpleMessage("Додати порт"),
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
    "agoDays": m3,
    "agoHours": m4,
    "agoMinutes": m5,
    "agoNow": MessageLookupByLibrary.simpleMessage("щойно"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage(
      "Допускати всі лінки",
    ),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Кожен новий CN цього CA одразу стає лінком, без схвалення. Витеклий сертифікат теж пройде.",
    ),
    "andWord": MessageLookupByLibrary.simpleMessage("і"),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "applyChanges": m6,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Застосувати профіль"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveCount": m7,
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "approveNone": MessageLookupByLibrary.simpleMessage(
      "Позначте хоча б один крок.",
    ),
    "approveOtherSite": m8,
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення в Studio з\'явиться з наступним кроком. Поки що схвалюй через wyrm-agent.",
    ),
    "approveRefused": m9,
    "approveRefusedHint": MessageLookupByLibrary.simpleMessage(
      "Зніміть позначку з названого кроку й схваліть решту. Коли план виконано, попросіть пропущені кроки окремим завданням: їх схвалюють тоді.",
    ),
    "approveSigns": m10,
    "askAdminFor": m11,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має виклику, щоб надіслати запит адміністратору.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Запитати"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну або постав питання про мережу (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("просить приєднатися"),
    "asksToJoinRelays": m12,
    "asksToRelay": m13,
    "auditDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "Аудит потребує рівня config на sys/audit.",
    ),
    "auditRefused": m14,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "backupPassphrase": MessageLookupByLibrary.simpleMessage(
      "Парольна фраза копії",
    ),
    "backupPassphraseNote": MessageLookupByLibrary.simpleMessage(
      "Лише для копії, запечатаної парольною фразою. Копія, запечатана для свого сайту, фрази не потребує і відкривається лише на брокері з ключами того сайту. Studio її не зберігає.",
    ),
    "backupReplaces": m15,
    "backupRightsAsk": MessageLookupByLibrary.simpleMessage(
      "брокер запитає за потреби",
    ),
    "backupRightsNote": MessageLookupByLibrary.simpleMessage(
      "Потрібно, коли лінк має права або список дозволених мереж: без цього брокер показує їх і нічого не встановлює. Токен, сертифікат і ключ запитувача будуть нові.",
    ),
    "bakAbout": m16,
    "bakAll": MessageLookupByLibrary.simpleMessage("Усе"),
    "bakBackUp": MessageLookupByLibrary.simpleMessage("Створити копію…"),
    "bakCancelDownload": MessageLookupByLibrary.simpleMessage(
      "Скасувати завантаження",
    ),
    "bakCard": MessageLookupByLibrary.simpleMessage("Резервні копії"),
    "bakCardEmpty": MessageLookupByLibrary.simpleMessage(
      "На брокері немає резервних копій.",
    ),
    "bakCardNote": m17,
    "bakCardOld": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має резервних копій зі Studio (на ньому wyrmd до ADR 0048). Скористайтеся командами нижче.",
    ),
    "bakChooseConnection": MessageLookupByLibrary.simpleMessage(
      "Виберіть лінк і з\'єднання",
    ),
    "bakChooseFolder": m18,
    "bakConsistent": MessageLookupByLibrary.simpleMessage(
      "Кожне сховище читається в один узгоджений момент, у власній транзакції читання; брокер працює і записує далі.",
    ),
    "bakDo": MessageLookupByLibrary.simpleMessage("Створити копію"),
    "bakDoLink": m19,
    "bakDoneSub": m20,
    "bakDoneTitle": MessageLookupByLibrary.simpleMessage(
      "Резервна копія готова",
    ),
    "bakDownload": MessageLookupByLibrary.simpleMessage("Завантажити…"),
    "bakDownloading": m21,
    "bakFactBy": MessageLookupByLibrary.simpleMessage("Створив"),
    "bakFactContents": MessageLookupByLibrary.simpleMessage("Вміст"),
    "bakFactLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "bakFactSealed": MessageLookupByLibrary.simpleMessage("Секрети"),
    "bakFactSent": MessageLookupByLibrary.simpleMessage("Надіслано до"),
    "bakFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер не створив резервну копію",
    ),
    "bakFailedTitle": m22,
    "bakKeysNeedPassphrase": MessageLookupByLibrary.simpleMessage(
      "Введіть нижче парольну фразу щонайменше з 12 символів: нею запечатуються ключі.",
    ),
    "bakKeysNeverSent": MessageLookupByLibrary.simpleMessage(
      "Резервну копію з ключами й секретами не надсилають: завантажте її на власному шлюзі сайту.",
    ),
    "bakKeysWarning": m23,
    "bakKindFull": MessageLookupByLibrary.simpleMessage("брокер"),
    "bakKindLink": m24,
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
    "bakPassphraseShort": m25,
    "bakProgressSub": MessageLookupByLibrary.simpleMessage(
      "Можна закрити; брокер завершить і збереже її в резервних копіях.",
    ),
    "bakProgressTitle": m26,
    "bakRemoveNote": MessageLookupByLibrary.simpleMessage(
      "Файл видаляється з брокера. Завантажена чи надіслана копія залишається.",
    ),
    "bakRemoveRow": MessageLookupByLibrary.simpleMessage(
      "Видалити її з брокера",
    ),
    "bakRemoveTitle": m27,
    "bakRestore": MessageLookupByLibrary.simpleMessage("Відновити…"),
    "bakRowFailed": MessageLookupByLibrary.simpleMessage("помилка"),
    "bakRowRunning": m28,
    "bakRowSending": m29,
    "bakSaved": m30,
    "bakSavedNote": m31,
    "bakSavedTo": m32,
    "bakSealedBroker": m33,
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
    "bakSendFailed": m34,
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
    "bakSending": m35,
    "bakSensitive": MessageLookupByLibrary.simpleMessage(
      "Резервна копія така ж чутлива, як каталог даних брокера: тримайте її там, куди мають доступ лише адміністратори.",
    ),
    "bakShow": MessageLookupByLibrary.simpleMessage(
      "Показати в резервних копіях",
    ),
    "bakSub": MessageLookupByLibrary.simpleMessage(
      "Виберіть, що потрапить у файл. Один файл .wyrm-backup (zip із маніфестом); брокер працює, поки його створюють.",
    ),
    "bakSubLink": m36,
    "bakTagAlways": MessageLookupByLibrary.simpleMessage("завжди"),
    "bakTagPassphrase": MessageLookupByLibrary.simpleMessage("парольна фраза"),
    "bakTagSite": MessageLookupByLibrary.simpleMessage(
      "запечатано для цього сайту",
    ),
    "bakTitle": m37,
    "bakTitleLink": m38,
    "bakWhatGoesIn": MessageLookupByLibrary.simpleMessage(
      "Що потрапляє у файл",
    ),
    "bakWhere": MessageLookupByLibrary.simpleMessage("Куди"),
    "bakWhereBroker": MessageLookupByLibrary.simpleMessage(
      "Залишити на брокері",
    ),
    "bakWhereBrokerNote": m39,
    "bakWhereComputer": MessageLookupByLibrary.simpleMessage("Цей комп\'ютер"),
    "bakWhereComputerNote": m40,
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
    "blocksCount": m41,
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
    "brokersDevices": m42,
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m43,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "bupBackOn": m44,
    "bupBackOnNote": m45,
    "bupCard": MessageLookupByLibrary.simpleMessage("Версія брокера"),
    "bupCardAvailable": m46,
    "bupCardCurrent": m47,
    "bupCardRolledBack": m48,
    "bupCardTrial": m49,
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
    "bupCheckSchemaNote": m50,
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
    "bupDoneRestart": m51,
    "bupDoneStaged": m52,
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
    "bupLinksBack": m53,
    "bupLost": m54,
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
    "bupOpenLog": m55,
    "bupPillContainer": MessageLookupByLibrary.simpleMessage("контейнер"),
    "bupPillRestarting": MessageLookupByLibrary.simpleMessage("перезапуск"),
    "bupReconnecting": MessageLookupByLibrary.simpleMessage("Під\'єднання…"),
    "bupRestarting": m56,
    "bupRollBackNote": MessageLookupByLibrary.simpleMessage(
      "Брокер перезапуститься на попередній версії й відновить копію площини керування, зроблену перед оновленням. Зміни після оновлення втрачаються.",
    ),
    "bupRollBackTitle": m57,
    "bupRollBackUntil": m58,
    "bupRolledBack": MessageLookupByLibrary.simpleMessage(
      "Оновлення відкочено",
    ),
    "bupRuns": m59,
    "bupRunsNote": m60,
    "bupSeconds": m61,
    "bupShow": MessageLookupByLibrary.simpleMessage("Показати…"),
    "bupStep1": MessageLookupByLibrary.simpleMessage(
      "Резервна копія площини керування перед оновленням, секрети запечатано (зберігається до підтвердження оновлення).",
    ),
    "bupStep2": m62,
    "bupStep3": m63,
    "bupStep4": m64,
    "bupStep5": m65,
    "bupSub": MessageLookupByLibrary.simpleMessage(
      "З каналу випусків цього брокера · брокер перезапускається один раз",
    ),
    "bupTitle": m66,
    "bupType": m67,
    "bupUpdate": MessageLookupByLibrary.simpleMessage("Оновити…"),
    "bupUpdated": m68,
    "bupUpdating": m69,
    "bupUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Цей екран під\'єднується самостійно.",
    ),
    "caSigned": m70,
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
    "cbNote": m71,
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
    "childCount": m72,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Вибери рядок: вузол відкривається в дереві, значення — в інспекторі.",
    ),
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
    "closeLabel": MessageLookupByLibrary.simpleMessage("Закрити"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colDeployedBy": MessageLookupByLibrary.simpleMessage("Хто розгорнув"),
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
    "connectNote": m73,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Під’єднати до верхнього",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Далі"),
    "controlPlane": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "copiedValue": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "copyKey": MessageLookupByLibrary.simpleMessage("Копіювати ключ"),
    "copyKeys": MessageLookupByLibrary.simpleMessage("Копіювати ключі"),
    "copyValue": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "Архів пакета, який ви приносите: zip, URL, Git-репозиторій або один .wasm. Перевіряється перед встановленням.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "dataDir": m74,
    "dataflow": MessageLookupByLibrary.simpleMessage("Потік даних"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Його права тут забрано зараз, наступне з’єднання чекатиме в карантині. Його сайти лишаються під ним.",
    ),
    "deauthorizeTitle": m75,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Вирішити в Лінках"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Лінк у карантині схвалюють або відхиляють у Лінках › Карантин.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "deploy": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "deployAskMessage": m76,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage(
      "Розгорнути цей потік?",
    ),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Щоб розгорнути, повернися до флоу",
    ),
    "deployedByWho": m77,
    "deploying": MessageLookupByLibrary.simpleMessage("Розгортання…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Усі частини дизайн-системи (лише для розробки).",
    ),
    "disableUser": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнений користувач не може увійти; ролі лишаються.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "doneLeftOutNote": m78,
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "Задачу виконано. План і журнал лишаються в її записі.",
    ),
    "doneOnTheDevice": m79,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("нижче"),
    "downstreamBroker": MessageLookupByLibrary.simpleMessage("Брокер нижче"),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "draftSaved": MessageLookupByLibrary.simpleMessage("Чернетку збережено"),
    "draftValid": MessageLookupByLibrary.simpleMessage(
      "Чернетка · правильна, не розгорнута",
    ),
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
    "editParamsOf": m80,
    "enableUser": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "errAdviceBroker": m81,
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
    "errAdviceInputField": m82,
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
    "errAdviceRightsRole": m83,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо повторюється, перезапустіть Studio.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Цей брокер або лінк не має такого виклику; можливо, він старіший, ніж очікує Studio.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Назад до форми"),
    "errCallOn": m84,
    "errChipStudio": m85,
    "errCopied": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage(
      "Копіювати подробиці",
    ),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Копіювати звіт"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Подробиці"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "Подробиці в буфері обміну.",
    ),
    "errDoDeploy": m86,
    "errDoInstall": m87,
    "errDoList": m88,
    "errDoLogIn": m89,
    "errDoOpen": m90,
    "errDoRead": m91,
    "errDoRemove": m92,
    "errDoRun": m93,
    "errDoSave": m94,
    "errDoStart": m95,
    "errDoStep": m96,
    "errDoStop": m97,
    "errDoWrite": m98,
    "errDoingDeploy": m99,
    "errDoingInstall": m100,
    "errDoingList": m101,
    "errDoingLogIn": m102,
    "errDoingOpen": m103,
    "errDoingRead": m104,
    "errDoingRemove": m105,
    "errDoingRun": m106,
    "errDoingSave": m107,
    "errDoingStart": m108,
    "errDoingStop": m109,
    "errDoingWrite": m110,
    "errFaultMessage": MessageLookupByLibrary.simpleMessage(
      "Тут стався збій у Studio. Це помилка Studio, а не брокера; більше нічого не надіслано.",
    ),
    "errNounDeploy": MessageLookupByLibrary.simpleMessage("розгортання"),
    "errNounInstall": MessageLookupByLibrary.simpleMessage("встановлення"),
    "errNounList": MessageLookupByLibrary.simpleMessage("список"),
    "errNounLogIn": MessageLookupByLibrary.simpleMessage("вхід"),
    "errNounOpen": MessageLookupByLibrary.simpleMessage("відкриття"),
    "errNounRead": MessageLookupByLibrary.simpleMessage("читання"),
    "errNounRemove": MessageLookupByLibrary.simpleMessage("вилучення"),
    "errNounRun": m111,
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
    "errSaidBroker": MessageLookupByLibrary.simpleMessage("Брокер відповів"),
    "errSaidNoAnswer": MessageLookupByLibrary.simpleMessage("Studio чекала"),
    "errSaidStudio": MessageLookupByLibrary.simpleMessage("Що сталося"),
    "errSeeAccess": MessageLookupByLibrary.simpleMessage("Мої права"),
    "errSilentReach": m112,
    "errSilentStatus": m113,
    "errStatusLine": m114,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("це"),
    "errTimeLocal": m115,
    "errTitleBroker": m116,
    "errTitleBrokerNoSite": m117,
    "errTitleBusy": m118,
    "errTitleGone": m119,
    "errTitleHistory": m120,
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
    "errTitleReach": m121,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "Брокер не відповідає",
    ),
    "errTitleRead": m122,
    "errTitleRights": m123,
    "errTitleStream": m124,
    "errTitleStudio": m125,
    "errTitleUnsupported": m126,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще раз"),
    "errTryAgainIn": m127,
    "errUserRole": m128,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("Що можна зробити"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "Запис, що не дочекався відповіді, міг бути застосований. Перевірте значення, перш ніж надсилати знову.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("ще не було"),
    "everySeconds": m129,
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
    "factSince": MessageLookupByLibrary.simpleMessage("Від"),
    "factStarted": MessageLookupByLibrary.simpleMessage("Запущено"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Стан"),
    "factSubject": MessageLookupByLibrary.simpleMessage("Суб’єкт"),
    "factTask": MessageLookupByLibrary.simpleMessage("Задача"),
    "factTaskState": MessageLookupByLibrary.simpleMessage("Стан"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Через"),
    "factTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Верхні"),
    "factValues": MessageLookupByLibrary.simpleMessage("Значення"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
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
    "fatalMoveFailed": m130,
    "fatalNote": m131,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Вийти зі Studio"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося запустити",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "Решта Studio працює; значення та дії в інших місцях не зачеплено.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Намалювати ще раз"),
    "faultProblem": m132,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("цю частину"),
    "faultTitle": m133,
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
    "firesAtDeploy": MessageLookupByLibrary.simpleMessage(
      "спрацює при розгортанні",
    ),
    "firesAtDeployNote": MessageLookupByLibrary.simpleMessage(
      "Параметр надсилає значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firesAtStartNote": MessageLookupByLibrary.simpleMessage(
      "Це поле надсилає своє значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firstSeen": m134,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "Чернетка не проходить перевірку.",
    ),
    "flowBack": MessageLookupByLibrary.simpleMessage("Назад"),
    "flowDeployed": m135,
    "flowError": m136,
    "flowName": MessageLookupByLibrary.simpleMessage("Ідентифікатор потоку"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Кожне поле має значення, вхід і вихід. Введіть значення або перетягніть на нього будь-який вихід, щоб зв’язати.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле показує значення, яке надходить; його зв’язок і джерело світяться, коли на нього навести. Значок зв’язку веде до джерела або розв’язує.",
    ),
    "flowStopped": m137,
    "flowVersion": m138,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "Розгортання потребує config на dataflows; gateway додає ваші докази для кожної цілі. Глядачі можуть лише дивитися.",
    ),
    "flowsOn": m139,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Кожен потік працює в брокері. Ви редагуєте чернетку; нічого не змінюється до розгортання.",
    ),
    "fmBlocks": m140,
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
    "fmUnpin": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "fmUnpinField": m141,
    "followUpAsk": m142,
    "followUpLeftOut": MessageLookupByLibrary.simpleMessage(
      "Попросити пропущені кроки",
    ),
    "fromAddress": m143,
    "fromBackup": MessageLookupByLibrary.simpleMessage("З резервної копії"),
    "fromBackupNote": MessageLookupByLibrary.simpleMessage(
      "Резервна копія лінка (.wyrm-link), створена дією «Резервна копія…» на лінку: налаштування, приватні дані й пакет. Повертається під своїм або новим ідентифікатором.",
    ),
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m144,
    "gatewayNoAnswer": m145,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Користувач gateway"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m146,
    "goToSource": MessageLookupByLibrary.simpleMessage("До джерела"),
    "goUp": MessageLookupByLibrary.simpleMessage("Вгору"),
    "grantFor": m147,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Ключ або шаблон"),
    "groupBackup": MessageLookupByLibrary.simpleMessage("Резервна копія"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Змінити"),
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
    "hidePassword": MessageLookupByLibrary.simpleMessage("Сховати пароль"),
    "historianKeep": m148,
    "historianSeries": m149,
    "historianSize": m150,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Лінки синхронізації читають журнал змін історика, тож нічого не губиться, поки база недоступна.",
    ),
    "historyOf": m151,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "історія недоступна",
    ),
    "historyUnavailableTip": m152,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Імпорт CSV або дерева DSA",
    ),
    "inputsCount": m153,
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
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Встановлення потребує config на sys (роль admin). Нічого не встановлюється, доки ви не натиснете «Встановити».",
    ),
    "installedOn": m154,
    "instancesInFlow": m155,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Видати"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Ключ скопійовано"),
    "keysCopied": m156,
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
    "lag": m157,
    "languageName": MessageLookupByLibrary.simpleMessage("Українська"),
    "lastRead": m158,
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
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksAlready": m159,
    "linksCount": m160,
    "linksLocalNote": m161,
    "linksOn": m162,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "listAnd": m163,
    "listFailedTip": m164,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "Ви не можете читати всі джерела й цілі цього потоку",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("Рядків немає."),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInLead": MessageLookupByLibrary.simpleMessage(
      "до gateway брокера. Ваша роль там визначає, що ви можете змінювати.",
    ),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть у gateway WYRM.",
    ),
    "logOf": m165,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
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
    "mayDoNote": MessageLookupByLibrary.simpleMessage(
      "Це параметри самого link агента. Зміни їх у Links › Edit params.",
    ),
    "mbBackFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу повернися до флоу",
    ),
    "mbDelete": MessageLookupByLibrary.simpleMessage("Видалити"),
    "mbEdit": MessageLookupByLibrary.simpleMessage("Редагувати власний блок"),
    "mbInUse": m166,
    "mbInsideItself": MessageLookupByLibrary.simpleMessage(
      "Блок не може містити сам себе",
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
    "mbUpdateTo": m167,
    "mbUsed": m168,
    "mbVersion": m169,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Мова"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Інше"),
    "menuSubtitle": m170,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Тема"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Повідомлень роутера за секунду",
    ),
    "metaFailedTip": m171,
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Вбудований"),
    "modeEmbeddedNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера: найлегший; зупиняється разом із брокером.",
    ),
    "modeExternal": MessageLookupByLibrary.simpleMessage("Зовнішній"),
    "modeExternalNote": MessageLookupByLibrary.simpleMessage(
      "На іншій машині: під’єднується із сертифікатом цього сайту.",
    ),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Процес"),
    "modeProcessNote": MessageLookupByLibrary.simpleMessage(
      "Окремий процес на цьому хості; брокер стежить і перезапускає.",
    ),
    "modeWasmNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера в пісочниці: без файлів, лише дозволена мережа, обмеження пам’яті й часу. Визначається типом пакета.",
    ),
    "more": MessageLookupByLibrary.simpleMessage("Ще"),
    "moreBytes": m172,
    "moreLines": m173,
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
    "nSelected": m174,
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
    "needsLevelYouHave": m175,
    "needsLevelYouHaveIt": m176,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newCertificate": MessageLookupByLibrary.simpleMessage("новий сертифікат"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("Новий потік"),
    "newTask": MessageLookupByLibrary.simpleMessage("Нова задача"),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "no": MessageLookupByLibrary.simpleMessage("ні"),
    "noActionReason": m177,
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
    "noParamReason": m178,
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
    "noUpstream": m179,
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
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "Точка дерева. Точка лише для читання не має входу; зв’язок у записувану точку пише ~set.",
    ),
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
    "openInExplorer": MessageLookupByLibrary.simpleMessage("Відкрити в дереві"),
    "openInLinks": MessageLookupByLibrary.simpleMessage("Відкрити в Лінках"),
    "openInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Доступи, відкликання і видалення — у Лінках › На інших пристроях.",
    ),
    "openInside": MessageLookupByLibrary.simpleMessage("Відкрити вміст"),
    "openItsTree": MessageLookupByLibrary.simpleMessage("Відкрити його дерево"),
    "openItsTreeNote": m180,
    "openingTree": MessageLookupByLibrary.simpleMessage("Відкриваємо дерево"),
    "openingTreeOf": m181,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m182,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "pairsCount": m183,
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
    "paramCount": m184,
    "paramsJson": m185,
    "paramsNotJson": m186,
    "paramsNotObject": MessageLookupByLibrary.simpleMessage(
      "Параметри мають бути одним об’єктом JSON.",
    ),
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "~meta вузла, як його оголошує брокер: профіль, cfg і attr.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("пройшов"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "pickAPoint": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку в таблиці, щоб побачити її історію.",
    ),
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
    "pickPointHint": MessageLookupByLibrary.simpleMessage(
      "Клацніть точку, щоб побачити її тренд; ⌘/Ctrl-клацання додає до трьох.",
    ),
    "pickPointTrend": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку, щоб побачити її тренд",
    ),
    "pinField": MessageLookupByLibrary.simpleMessage("Закріпити на блоці"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле лишається на блоці",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Пінг"),
    "planCard": MessageLookupByLibrary.simpleMessage("План"),
    "planChecked": MessageLookupByLibrary.simpleMessage(
      "чекає на схвалення · перевірено",
    ),
    "planNeedsStep": m187,
    "planNote": MessageLookupByLibrary.simpleMessage(
      "План записаний у задачі. Studio покаже його, коли gateway зможе читати документи (docs/studio.md §10 п. 11). Поки що читай план через wyrm-agent.",
    ),
    "planSleep": m188,
    "planSteps": m189,
    "planTimeout": m190,
    "planWaiting": MessageLookupByLibrary.simpleMessage(
      "План чекає на схвалення. До нього нічого не виконується.",
    ),
    "planWhyNote": MessageLookupByLibrary.simpleMessage(
      "Рядки після «why» і попередження пише модель. Прочитай ключ і аргументи кожного кроку: виконується саме це.",
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
    "pointsCount": m191,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується в пристрій до застосування.",
    ),
    "portsCount": m192,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Читання блоків потоків",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Читання потоків"),
    "preloadLater": m193,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Читання лінків"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Читання сайтів"),
    "preloadTree": m194,
    "previewInvalid": m195,
    "previewTag": MessageLookupByLibrary.simpleMessage("перегляд"),
    "problems": MessageLookupByLibrary.simpleMessage("Проблеми"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Очистити все"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Закрити проблеми"),
    "problemsCount": m196,
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
    "qInstalled": m197,
    "qInstalling": m198,
    "qRun": MessageLookupByLibrary.simpleMessage(
      "Де він працюватиме і під якою назвою?",
    ),
    "quarantine": MessageLookupByLibrary.simpleMessage("Карантин"),
    "quarantineAndAdmission": MessageLookupByLibrary.simpleMessage(
      "Карантин і допуск",
    ),
    "quarantineAndAdmissionNote": MessageLookupByLibrary.simpleMessage(
      "Невідомі сертифікати чекають у Лінках › Карантин.",
    ),
    "reachesSites": m199,
    "readAgain": MessageLookupByLibrary.simpleMessage("Прочитати знову"),
    "readFailed": MessageLookupByLibrary.simpleMessage("не прочитано"),
    "readFailedTip": m200,
    "readsNote": MessageLookupByLibrary.simpleMessage(
      "Читання не потребує схвалення. Агент читає лише в межах ваших прав і своїх.",
    ),
    "recordInHistory": MessageLookupByLibrary.simpleMessage(
      "Записувати в історію…",
    ),
    "recorded": MessageLookupByLibrary.simpleMessage("записується"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "refuseLoop": MessageLookupByLibrary.simpleMessage(
      "Це замикає цикл (лише через delay)",
    ),
    "refuseNeedsBroker": m201,
    "refuseNoInput": m202,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Вихід не можна зв’язати",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "Блок не може живити сам себе",
    ),
    "refuseType": m203,
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectPlanHint": MessageLookupByLibrary.simpleMessage("Причина"),
    "rejectPlanNote": MessageLookupByLibrary.simpleMessage(
      "План не виконується. Причина зберігається в записі завдання.",
    ),
    "rejectPlanTitle": MessageLookupByLibrary.simpleMessage("Відхилити план?"),
    "rejectTitle": m204,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Звідси нічого робити: він прийшов разом зі своїм ретранслятором. Відкличте ретранслятор, щоб відрізати його.",
    ),
    "relaysSites": m205,
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
    "removeLinkTitle": m206,
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
    "removeUserTitle": m207,
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultOf": m208,
    "returns": m209,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "reviewNote": m210,
    "revision": m211,
    "revisionNow": m212,
    "rightsLine": m213,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "roleOnSite": m214,
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m215,
    "rowsAdd": MessageLookupByLibrary.simpleMessage("Додати рядок"),
    "rowsAnswered": m216,
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
    "rstFile": m217,
    "rstFileNote": m218,
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
    "rstLinks": m219,
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
    "rstOtherSite": m220,
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
    "rstReplaceKeys": m221,
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
    "rstRestarting": m222,
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
    "rstTitle": m223,
    "rstUnknown": MessageLookupByLibrary.simpleMessage("Брокер повернувся"),
    "rstUnknownNote": MessageLookupByLibrary.simpleMessage(
      "В аудиті ще немає ні restore_applied, ні restore_failed. Перегляньте Система › Журнал, перш ніж покладатися на відновлення.",
    ),
    "rstUploaded": MessageLookupByLibrary.simpleMessage("Файл на брокері"),
    "rstUploadedNote": MessageLookupByLibrary.simpleMessage(
      "Ще нічого не змінено. Перевірка читає маніфест і порівнює його з цим брокером.",
    ),
    "rstUploading": m224,
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
    "runNow": MessageLookupByLibrary.simpleMessage("Виконати"),
    "runNowNote": m225,
    "runOff": MessageLookupByLibrary.simpleMessage("Блок вимкнено"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Запускати на кожному старті?",
    ),
    "running": MessageLookupByLibrary.simpleMessage("Працює"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "Агент працює над задачею. Скасування зупиняє її; зроблене лишається.",
    ),
    "runsOn": m226,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
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
    "screenOf": m227,
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
    "seeLinks": MessageLookupByLibrary.simpleMessage("див. Лінки"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setLogLevel": m228,
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
    "showPassword": MessageLookupByLibrary.simpleMessage("Показати пароль"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Вхід…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Сайт, ретрансльований нижче",
    ),
    "sitesAround": m229,
    "sitesSubtitle": m230,
    "sizeBytes": m231,
    "sizeChars": m232,
    "sizeColumns": m233,
    "sizeItems": m234,
    "sizeKeys": m235,
    "sizeLines": m236,
    "sizeRows": m237,
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m238,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
    "stagedWas": m239,
    "stale": MessageLookupByLibrary.simpleMessage("застаріле"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Його резервний gateway відповідає на",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "standbyIs": m240,
    "stateConnected": MessageLookupByLibrary.simpleMessage("Під’єднано"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Збій"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Встановлено"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Офлайн"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Запускається"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Зупинено"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Зупиняється"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Чекає"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Принести"),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Перевірка"),
    "stepChecking": MessageLookupByLibrary.simpleMessage(
      "Перевірка користувача і пароля",
    ),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Вибір"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Встановлення"),
    "stepLeftOut": MessageLookupByLibrary.simpleMessage(
      "пропущено: не виконається",
    ),
    "stepOf": m241,
    "stepReaching": m242,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Читання вашої ролі та сайтів",
    ),
    "stepSkippedNeeds": m243,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "stopRecording": MessageLookupByLibrary.simpleMessage("Припинити запис"),
    "studioAbout": m244,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "studioVersion": m245,
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
    "sysAttnAcl": m246,
    "sysAttnAclDetail": m247,
    "sysAttnBehind": m248,
    "sysAttnBehindDetail": m249,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag більший за 0: перемикання зараз втратить записи",
    ),
    "sysAttnBroker": m250,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage("Нижчий брокер"),
    "sysAttnBrokerRelays": m251,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysAttnLinkDetail": m252,
    "sysAttnLinkFailed": m253,
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
    "sysAttnQuarantine": m254,
    "sysAttnQuarantineDetail": m255,
    "sysAttnQuarantineSince": m256,
    "sysBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія та відновлення",
    ),
    "sysBackupNote": m257,
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
    "sysBannerForks": m258,
    "sysBannerLag": m259,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("брокер (усе)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Рівень журналу брокера",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Байти"),
    "sysClear": m260,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Очистити ці від’єднані лінки?",
    ),
    "sysClearAskBody": m261,
    "sysClearBoard": m262,
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
    "sysCleared": m263,
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
    "sysCopyCommand": m264,
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
    "sysGuideCopied": m265,
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
    "sysLinkSource": m266,
    "sysLogCopied": m267,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Потрапляє до «Переглянути й застосувати»; після застосування діє одразу, без перезапуску, і замінює `RUST_LOG`. Zenoh лишається на warn нижче trace. Значення й токени не журналюються нижче trace. Власний рівень лінка: Лінки › лінк › Журнал.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Журнал читають із рівнем config на sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Не вдалося зберегти журнал",
    ),
    "sysLogSaved": m268,
    "sysLogSummary": m269,
    "sysLogSummaryAround": m270,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "sysMetaStarted": m271,
    "sysNeedsLook": m272,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "Зі значень самого брокера. Кожна картка відкриває екран, де це виправляють.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "На цьому рівні рядків немає.",
    ),
    "sysNoLinesAround": m273,
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
    "sysNoStandbyStep2": m274,
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
    "sysNow": m275,
    "sysOfTotal": m276,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Відкрити запис аудиту ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("вихід"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Пакети"),
    "sysProfileFile": m277,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Назва"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m278,
    "sysProfileRemoved": m279,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Профілі пристроїв"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Моделі, які брокер віддає як `pub/<vendor>:<model>`: точки, одиниці та діапазони, що їх успадковують лінки й асистент.",
    ),
    "sysProfilesUnlisted": m280,
    "sysPulled": MessageLookupByLibrary.simpleMessage("забирає щосекунди"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Додати профіль"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Додати профіль…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("записів"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Вилучити"),
    "sysRemoveProfile": m281,
    "sysRemoveProfileAsk": m282,
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
    "sysStaleRow": m283,
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
    "sysSubData": m284,
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
    "sysSubLinkFailed": m285,
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
    "sysSubPeer": m286,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "мережеві сесії; користувачів шлюзу не враховано",
    ),
    "sysSubWaits": m287,
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
    "sysTrafficDescribe": m288,
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
    "tableFiltered": m289,
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
    "tagNeeds": m290,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("чекає схвалення"),
    "taskAwaitingAnswer": MessageLookupByLibrary.simpleMessage(
      "чекає на твою відповідь",
    ),
    "taskBy": m291,
    "taskDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "taskFailed": MessageLookupByLibrary.simpleMessage(
      "не вдалося або зупинено",
    ),
    "taskFailedAt": m292,
    "taskListNote": m293,
    "taskNoChanges": MessageLookupByLibrary.simpleMessage("нічого не змінено"),
    "taskPlanning": MessageLookupByLibrary.simpleMessage("планує"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("виконує"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "tlsCertificateOf": m294,
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Закрити"),
    "toastHidesIn": m295,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Сповіщення"),
    "toastStays": m296,
    "toastStream": MessageLookupByLibrary.simpleMessage(
      "Studio відкриє потоки знову, коли він повернеться.",
    ),
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
    "treeEmpty": MessageLookupByLibrary.simpleMessage("Тут нічого немає."),
    "treeLoading": MessageLookupByLibrary.simpleMessage("Читаю дерево…"),
    "treeNoteLead": MessageLookupByLibrary.simpleMessage(
      "Дерево показує лише дані.",
    ),
    "treeNoteMiddle": MessageLookupByLibrary.simpleMessage("змінюється в"),
    "treeOf": m297,
    "treePoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "на блоці: додає її як поле. На полотні: новий блок цього вузла.",
    ),
    "treePointNote2": MessageLookupByLibrary.simpleMessage(
      "на полотні: блок, що її читає (записувана точка питає «Читати» чи «Писати»; Alt пише). На полі: прив\'язується до нього.",
    ),
    "trendAll": MessageLookupByLibrary.simpleMessage("усе"),
    "trendAllHidden": MessageLookupByLibrary.simpleMessage("Усі ряди сховано."),
    "trendAvg": m298,
    "trendBadRecorded": MessageLookupByLibrary.simpleMessage(
      "записано погану якість",
    ),
    "trendBucket": m299,
    "trendClearMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть A ще раз, щоб прибрати її",
    ),
    "trendDelta": m300,
    "trendDescribe": m301,
    "trendFollowNow": MessageLookupByLibrary.simpleMessage("До поточного часу"),
    "trendHint": MessageLookupByLibrary.simpleMessage(
      "Наведіть для значень · тягніть по графіку, щоб наблизити · клацніть, щоб поставити мітку A · тягніть або змінюйте вікно внизу · подвійне клацання скидає · ← → рухають вибрану ручку",
    ),
    "trendHoursMinutes": m302,
    "trendLocked": m303,
    "trendMarker": m304,
    "trendMinMax": m305,
    "trendMinutes": m306,
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
    "trendRaw": MessageLookupByLibrary.simpleMessage("сирі"),
    "trendRawAt": m307,
    "trendResetZoom": MessageLookupByLibrary.simpleMessage("Скинути масштаб"),
    "trendSeconds": m308,
    "trendSetMarker": MessageLookupByLibrary.simpleMessage(
      "Клацніть, щоб поставити мітку A",
    ),
    "trendShowHide": m309,
    "trendStepDays": m310,
    "trendStepHours": m311,
    "trendStepMinutes": m312,
    "trendUncertain": MessageLookupByLibrary.simpleMessage(
      "uncertain · застарілі читання в цьому інтервалі",
    ),
    "trendWeekdays": MessageLookupByLibrary.simpleMessage(
      "Пн,Вт,Ср,Чт,Пт,Сб,Нд",
    ),
    "trendWindowEnd": MessageLookupByLibrary.simpleMessage("Кінець вікна"),
    "trendWindowStart": MessageLookupByLibrary.simpleMessage("Початок вікна"),
    "tryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "unbind": MessageLookupByLibrary.simpleMessage("Розв’язати"),
    "unitNumber": m313,
    "unpinField": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "Брокер, можливо, перезапускається, або цей комп’ютер в іншій мережі.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "Точка більше не записується; рядки лишаються.",
    ),
    "upFor": m314,
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
    "updDo": m315,
    "updFailed": m316,
    "updFailedNote": MessageLookupByLibrary.simpleMessage(
      "Перевірка стану закінчилась без відповіді від кожного лінка.",
    ),
    "updFromFile": MessageLookupByLibrary.simpleMessage("Новіший архів"),
    "updFromFileNote": m317,
    "updFromFileRow": MessageLookupByLibrary.simpleMessage("Оновити з файлу…"),
    "updGoneTile": MessageLookupByLibrary.simpleMessage("зникли"),
    "updHotStart": m318,
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
    "updKeptUntil": m319,
    "updLeave": MessageLookupByLibrary.simpleMessage(
      "Можна піти з цього екрана; оновлення триває.",
    ),
    "updLinksCount": m320,
    "updLinksRestart": m321,
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
    "updOpenLink": m322,
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
    "updPointBeforeRestore": m323,
    "updPointBeforeUpdate": m324,
    "updPoints": MessageLookupByLibrary.simpleMessage("Точки відновлення"),
    "updRights": MessageLookupByLibrary.simpleMessage("Права і мережа"),
    "updRightsNote": MessageLookupByLibrary.simpleMessage(
      "Якщо нова версія просить більше, ніж мають лінки, брокер нічого не встановлює і показує перелік тут для прийняття.",
    ),
    "updRollBack": MessageLookupByLibrary.simpleMessage("Відкотити"),
    "updRollBackNote": m325,
    "updRollBackTitle": m326,
    "updRollBackTo": m327,
    "updRolledBackNote": MessageLookupByLibrary.simpleMessage(
      "Лінки знову працюють на збереженій версії.",
    ),
    "updRolledBackTo": m328,
    "updRowChecking": MessageLookupByLibrary.simpleMessage("перевіряється"),
    "updRuns": m329,
    "updRunsNote": m330,
    "updStateChanges": m331,
    "updStateChangesNote": MessageLookupByLibrary.simpleMessage(
      "Стара версія не читає нове сховище: відкат відновлює сховище з точки відновлення.",
    ),
    "updStateCustom": MessageLookupByLibrary.simpleMessage(
      "Формат сховища: каже архів",
    ),
    "updStateCustomNote": MessageLookupByLibrary.simpleMessage(
      "Якщо архів не читає встановлений формат сховища, брокер відмовляє в оновленні без точки відновлення.",
    ),
    "updStateSame": m332,
    "updStateSameNote": MessageLookupByLibrary.simpleMessage(
      "Нова версія читає сховище встановленої.",
    ),
    "updStepNodes": MessageLookupByLibrary.simpleMessage(
      "Стан: кожен лінк повернувся зі своїми вузлами",
    ),
    "updStepNodesCount": m333,
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
    "updSubCustom": m334,
    "updSubOfficial": m335,
    "updTab": MessageLookupByLibrary.simpleMessage("Оновлення"),
    "updTabNote": MessageLookupByLibrary.simpleMessage(
      "Лінки, пакет яких має новішу версію. Усі лінки пакета оновлюються разом, і брокер зберігає потрібне для повернення.",
    ),
    "updThen": MessageLookupByLibrary.simpleMessage("Потім"),
    "updTitle": m336,
    "updTitleCustom": m337,
    "updTitleDone": m338,
    "updTitleRolledBack": m339,
    "updTogether": MessageLookupByLibrary.simpleMessage("оновлюються разом"),
    "updUpdating": m340,
    "updUpdatingButton": MessageLookupByLibrary.simpleMessage("Оновлення…"),
    "updUpdatingSub": MessageLookupByLibrary.simpleMessage(
      "Значення його лінків зупиняються на час перезапуску.",
    ),
    "updVersionsOf": m341,
    "updWhatChanges": MessageLookupByLibrary.simpleMessage(
      "Що змінюється для брокера",
    ),
    "updWhatIsNew": m342,
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
    "versionDeployed": m343,
    "viaSite": m344,
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
    "viewerCsvRules": m345,
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
    "viewerSaveHint": m346,
    "viewerTabTable": MessageLookupByLibrary.simpleMessage("Як таблиця"),
    "viewerTabText": MessageLookupByLibrary.simpleMessage("Текст"),
    "viewerTableHint": m347,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "waitingToBeLetIn": m348,
    "wasValue": m349,
    "wasWord": MessageLookupByLibrary.simpleMessage("було"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Група спостереження"),
    "watchGroups": m350,
    "welcomeUser": m351,
    "whatItRead": MessageLookupByLibrary.simpleMessage("Що прочитано"),
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
    "whyNew": MessageLookupByLibrary.simpleMessage("Новий"),
    "whyRunBackup": MessageLookupByLibrary.simpleMessage(
      "Залиште його ідентифікатор, щоб відновити, або дайте новий, щоб створити другий лінк. Режим той, у якому він працював.",
    ),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер. Лише брокери, для чийого хоста зібрано пакет, можуть його прийняти; спосіб роботи задає тип пакета.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер, потім як лінк на ньому працюватиме. Вбудований драйвер може працювати в брокері, окремим процесом або на іншій машині.",
    ),
    "windowClose": MessageLookupByLibrary.simpleMessage("Закрити вікно"),
    "windowMaximize": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "windowMinimize": MessageLookupByLibrary.simpleMessage("Згорнути"),
    "windowRestore": MessageLookupByLibrary.simpleMessage("Відновити"),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Задається типом даних: суфіксом _wswap, _bswap або _wbswap.",
    ),
    "wouldRun": m352,
    "wouldSend": m353,
    "wouldWrite": m354,
    "writableNeeds": m355,
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
    "wyrmdOn": m356,
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
