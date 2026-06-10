# British Citizen Act

## Assumptions

<!-- l4: assume:Person -->

**1.** In this Act, “Person” denotes a type.

<!-- l4: assume:mother of -->

**2.** In this Act, “mother of” denotes a function yielding a Person.

<!-- l4: assume:father of -->

**3.** In this Act, “father of” denotes a function yielding a Person.

<!-- l4: assume:is born in the United Kingdom after commencement -->

**4.** In this Act, “is born in the United Kingdom after commencement” denotes a function yielding a BOOLEAN.

<!-- l4: assume:is born in a qualifying territory after the appointed day -->

**5.** In this Act, “is born in a qualifying territory after the appointed day” denotes a function yielding a BOOLEAN.

<!-- l4: assume:is settled in the United Kingdom -->

**6.** In this Act, “is settled in the United Kingdom” denotes a function yielding a BOOLEAN.

<!-- l4: assume:is settled in the qualifying territory in which the person is born -->

**7.** In this Act, “is settled in the qualifying territory in which the person is born” denotes a function yielding a BOOLEAN.

## Improved Readability Version

<!-- l4: declare:Place -->

**8.** In this Act, “Place” means a record consisting of—

    (a) “English name”, being a STRING.

<!-- l4: decide:British Overseas Territories -->

**9.** British Overseas Territories means list of Place with Anguilla, Place with Bermuda, Place with British Antarctic Territory, Place with British Indian Ocean Territory, Place with Cayman Islands, Place with Falkland Islands, Place with Gibraltar, Place with Hong Kong, Place with Montserrat, Place with Pitcairn, Henderson, Ducie and Oeno Islands, Place with St Helena, Ascension and Tristan da Cunha, Place with South Georgia and the South Sandwich Islands, Place with The Sovereign Base Areas of Akrotiri and Dhekelia, Place with Turks and Caicos Islands and Place with Virgin Islands.

<!-- l4: decide:isBOT -->

**10.** In relation to a Place “p”, isBOT if—

    (a) p's English name is equal to Anguilla;

    (b) p's English name is equal to Bermuda;

    (c) p's English name is equal to British Antarctic Territory;

    (d) p's English name is equal to British Indian Ocean Territory;

    (e) p's English name is equal to Cayman Islands;

    (f) p's English name is equal to Falkland Islands;

    (g) p's English name is equal to Gibraltar;

    (h) p's English name is equal to Hong Kong;

    (i) p's English name is equal to Montserrat;

    (j) p's English name is equal to Pitcairn, Henderson, Ducie and Oeno Islands;

    (k) p's English name is equal to St Helena, Ascension and Tristan da Cunha;

    (l) p's English name is equal to Sovereign Base Areas of Akrotiri and Dhekelia;

    (m) p's English name is equal to South Georgia and the South Sandwich Islands;

    (n) p's English name is equal to Turks and Caicos Islands; or

    (o) p's English name is equal to Virgin Islands.

<!-- l4: decide:akdh -->

**11.** Akdh means Place where English name is Sovereign Base Areas of Akrotiri and Dhekelia.

<!-- l4: declare:Date -->

**12.** In this Act, “Date” means a record consisting of—

    (a) “year”, being a NUMBER;

    (b) “month”, being a NUMBER; and

    (c) “day”, being a NUMBER.

<!-- l4: decide:commencement -->

**13.** Commencement means Date with 1983, 1 and 1.

<!-- l4: decide:appointed day -->

**14.** Appointed day means Date with 2002, 2 and 21.

<!-- l4: decide:qualifying territory -->

**15.** In relation to a Place “p”, qualifying territory if—

    (a) isBOT with p; and

    (b) p's English name is not equal to Sovereign Base Areas of Akrotiri and Dhekelia.

<!-- l4: declare:Maybe -->

**16.** In this Act, “Maybe” means one of the following—

    (a) “Nothing”; or

    (b) “Just”, having a “val” (an a).

<!-- l4: declare:NaturalPerson -->

**17.** In this Act, “NaturalPerson” means a record consisting of—

    (a) “mama”, being a Maybe Person;

    (b) “papa”, being a Maybe Person;

    (c) “birthPlace”, being a Maybe Place; and

    (d) “birthDate”, being a Maybe Date.

<!-- l4: decide:after -->

**18.** In relation to a Date “d” and a Date “c”, after means the sum of the sum of the product of the difference between 1900 and year with c and 365 and the product of month with c and 30 and day with c is less than the sum of the sum of the product of the difference between 1900 and d's year and 365 and the product of d's month and 30 and d's day.

<!-- l4: decide:isBornInUK -->

**19.** In relation to a NaturalPerson “p”, isBornInUK means UK is equal to English name with p's birthPlace's val.

<!-- l4: decide:isBornInUS -->

**20.** In relation to “p”, isBornInUS means US is equal to English name with p's birthPlace's val.

<!-- l4: decide:afterCommencement -->

**21.** In relation to “p”, afterCommencement means after with p's birthDate's val and commencement.

<!-- l4: decide:afterAppointedDay -->

**22.** In relation to “p”, afterAppointedDay means after with p's birthDate's val and appointed day.

<!-- l4: decide:plus -->

**23.** In relation to a NUMBER “a” and a NUMBER “b”, plus means the sum of a and b.

## Expanded version

<!-- l4: decide:is a British citizen if anything -->

**24.** In relation to a Person “p” and a BOOLEAN “a”, is a British citizen if anything if—

    (a) any of the following applies—

        (i) is born in the United Kingdom after commencement with p; or

        (ii) is born in a qualifying territory after the appointed day with p; and

    (b) any of the following applies—

        (i) is a British citizen if anything with father of with p and a;

        (ii) is a British citizen if anything with mother of with p and a;

        (iii) is settled in the United Kingdom with father of with p;

        (iv) is settled in the United Kingdom with mother of with p;

        (v) is settled in the qualifying territory in which the person is born with father of with p; or

        (vi) is settled in the qualifying territory in which the person is born with mother of with p.

## Version using a local auxiliary declaration

<!-- l4: decide:is a British citizen (local) -->

**25.** In relation to a Person “p”, is a British citizen (local) if—

    (a) any of the following applies—

        (i) is born in the United Kingdom after commencement with p; or

        (ii) is born in a qualifying territory after the appointed day with p; and

    (b) any of the following applies—

        (i) father or mother with is settled in the United Kingdom; or

        (ii) father or mother with is settled in the qualifying territory in which the person is born.

For the purposes of this provision—

“father or mother” means property with father of with p or property with mother of with p;

## Version using a global auxiliary declaration

<!-- l4: decide:for father or mother of -->

**26.** In relation to “person” and “property”, for father or mother of if—

    (a) property with father of with person; or

    (b) property with mother of with person.

<!-- l4: decide:is a British citizen (variant) -->

**27.** In relation to a Person “p”, is a British citizen (variant) if—

    (a) any of the following applies—

        (i) is born in the United Kingdom after commencement with p; or

        (ii) is born in a qualifying territory after the appointed day with p; and

    (b) any of the following applies—

        (i) for father or mother of with p and is a British citizen (variant);

        (ii) for father or mother of with p and is settled in the United Kingdom; or

        (iii) for father or mother of with p and is settled in the qualifying territory in which the person is born.

<!-- tnr-coverage: 27 provisions; 0 boolean atoms inlined; 2 directives suppressed -->
