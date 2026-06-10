# New York Codes, Rules and Regulations

## Title 16 - DEPARTMENT OF PUBLIC SERVICE

### Chapter I - RULES OF PROCEDURE

#### Subchapter A - GENERAL

##### Part 7 - Implementation Of State Environmental Quality Review Act

###### Section 7.3 - Environmental review procedures

###### Section 7.3 (a)

<!-- l4: declare:Commission -->

**1.** In this Act, “Commission” means a record consisting of—

    (a) “Name”, being a STRING.

<!-- l4: declare:Newspaper -->

**2.** In this Act, “Newspaper” means a record consisting of—

    (a) “Name”, being a STRING; and

    (b) “General circulation area”, being a STRING.

<!-- l4: declare:Notice -->

**3.** In this Act, “Notice” means a record consisting of—

    (a) “Publish date”, being a DATE;

    (b) “Scheduled date”, being a DATE;

    (c) “Publishing medium”, being a Newspaper; and

    (d) “Is in accordance with the requirements of 6 NYCRR 617.10”, being a BOOLEAN.

<!-- l4: declare:Applicant -->

**4.** In this Act, “Applicant” means a record consisting of—

    (a) “Name”, being a STRING.

<!-- l4: declare:File draft copy of EIS and cause notice of hearing to be published -->

**5.** In this Act, “File draft copy of EIS and cause notice of hearing to be published” means a record consisting of—

    (a) “Hearing Notice”, being a Notice;

    (b) “Notice of EIS Completion”, being a Notice; and

    (c) “Prepared draft copy of EIS”, being a MAYBE Environmental Impact Statement.

<!-- l4: declare:Action that may have a significant adverse effect on the environment -->

**6.** In this Act, “Action that may have a significant adverse effect on the environment” means a record consisting of—

    (a) “Proposed by”, being an Applicant;

    (b) “Lead agency”, being a Commission;

    (c) “Potential effect area”, being a STRING;

    (d) “Has hearing required by statute”, being a BOOLEAN;

    (e) “Has been withdrawn”, being a BOOLEAN; and

    (f) “EIS”, being an Environmental Impact Statement.

<!-- l4: declare:Environmental Impact Statement -->

**7.** In this Act, “Environmental Impact Statement” means a record consisting of—

    (a) “Draft filing date”, being a DATE; and

    (b) “Final filing date”, being a MAYBE DATE.

<!-- l4: decide:Filing of draft copy of EIS and causing notice of hearing to be published -->

**8.** In relation to a Commission “The commission” and an Action that may have a significant adverse effect on the environment “The action”, Filing of draft copy of EIS and causing notice of hearing to be published means if The commission is equal to The action's Lead agency and The action's Has hearing required by statute, then The commission must File draft copy of EIS and cause notice of hearing to be published has Hearing Notice, Notice of EIS Completion and Prepared draft copy of EIS, provided that Hearing Notice's Scheduled date is at least the sum of Hearing Notice's Publish date and 14 and Hearing Notice's Scheduled date is at most the sum of Hearing Notice's Publish date and 60 and consider the case distinctions of Prepared draft copy of EIS :  when NOTHING has  then FALSE. when JUST has EIS then Hearing Notice's Scheduled date is at least the sum of EIS's Draft filing date and 15 and Hearing Notice's Scheduled date is at most the sum of EIS's Draft filing date and 60 and Hearing Notice's Publishing medium's General circulation area is equal to The action's Potential effect area and Hearing Notice's Is in accordance with the requirements of 6 NYCRR 617.10 and Notice of EIS Completion's Is in accordance with the requirements of 6 NYCRR 617.10, within Day with the week after with March with 2 and 2028. Upon compliance, FULFILLED.; otherwise, FULFILLED.

<!-- l4: decide:Example Commission -->

**9.** Example Commission means Commission where Name is A commission.

<!-- l4: decide:Example EIS -->

**10.** Example EIS means Environmental Impact Statement where Draft filing date is Jul with 19 and 2025 and Final filing date is NOTHING.

<!-- l4: decide:Example Action -->

**11.** Example Action means Action that may have a significant adverse effect on the environment where Proposed by is Applicant where Name is An applicant, Lead agency is Example Commission, Potential effect area is Brooklyn, Has hearing required by statute is TRUE, Has been withdrawn is FALSE and EIS is Example EIS.

<!-- l4: decide:Example Filing -->

**12.** Example Filing means Filing of draft copy of EIS and causing notice of hearing to be published with Example Commission and Example Action.

<!-- l4: decide:Example Newspaper -->

**13.** Example Newspaper means Newspaper with New York Times and Brooklyn.

<!-- l4: decide:Example Hearing Notice -->

**14.** Example Hearing Notice means Notice where Publish date is Jul with 20 and 2025, Scheduled date is Aug with 1 and 2025, Publishing medium is Example Newspaper and Is in accordance with the requirements of 6 NYCRR 617.10 is TRUE.

<!-- l4: decide:Example Notice of EIS Completion -->

**15.** Example Notice of EIS Completion means Notice where Publish date is Jul with 20 and 2025, Scheduled date is Aug with 8 and 2025, Publishing medium is Example Newspaper and Is in accordance with the requirements of 6 NYCRR 617.10 is TRUE.

###### Section 7.3 (b)

###### Section 7.3 (b) (1)

<!-- l4: declare:Proceeding Record -->

**16.** In this Act, “Proceeding Record” means a record consisting of—

    (a) “Closing date”, being a DATE.

<!-- l4: declare:Tentative or recommended decision -->

**17.** In this Act, “Tentative or recommended decision” means a record consisting of—

    (a) “Action”, being an Action that may have a significant adverse effect on the environment;

    (b) “Proceeding Record”, being a Proceeding Record; and

    (c) “On the basis of the record of the proceeding (including the draft EIS and any comments received thereon), the Administrative Law Judge issuing this decision determined that the action will not have a significant adverse effect on the environment”, being a BOOLEAN.

<!-- l4: decide:Tentative or recommended decision will contain a final EIS -->

**18.** In relation to a Tentative or recommended decision “The decision”, Tentative or recommended decision will contain a final EIS means if not The decision's Action's Has been withdrawn and not The decision's On the basis of the record of the proceeding (including the draft EIS and any comments received thereon), the Administrative Law Judge issuing this decision determined that the action will not have a significant adverse effect on the environment, then TRUE; otherwise, FALSE.

<!-- l4: decide:Example Proceeding Record -->

**19.** Example Proceeding Record means Proceeding Record where Closing date is Date with Aug, 20 and 2025.

<!-- l4: decide:Example Decision -->

**20.** Example Decision means Tentative or recommended decision where Action is Example Action, Proceeding Record is Example Proceeding Record and On the basis of the record of the proceeding (including the draft EIS and any comments received thereon), the Administrative Law Judge issuing this decision determined that the action will not have a significant adverse effect on the environment is TRUE.

###### Section 7.3 (b) (2)

<!-- l4: declare:Final EIS Issuance Extension Cause -->

**21.** In this Act, “Final EIS Issuance Extension Cause” means one of the following—

    (a) “(i) Additional time is necessary to prepare the EIS adequately”;

    (b) “(ii) Problems have been identified which require the material reconsideration or modification of the action”; or

    (c) “(iii) Other good cause”.

<!-- l4: declare:Final EIS Issuance -->

**22.** In this Act, “Final EIS Issuance” means one of the following—

    (a) “No issuance”;

    (b) “Issued within 45 days of the close of the record”; or

    (c) “Issued extended beyond 45 days of the close of the record”.

<!-- l4: decide:Determining issuance for final EIS -->

**23.** In relation to a Tentative or recommended decision “The decision” and a MAYBE Final EIS Issuance Extension Cause “Cause for extension”, Determining issuance for final EIS means if not Tentative or recommended decision will contain a final EIS with The decision, then No issuance; otherwise, consider the case distinctions of Cause for extension :  when NOTHING has  then Issued within 45 days of the close of the record. when JUST has cause then Issued extended beyond 45 days of the close of the record.

<!-- l4: decide:Determining days till issuance for final EIS -->

**24.** In relation to a Tentative or recommended decision “The decision”, a MAYBE Final EIS Issuance Extension Cause “Cause for extension” and a NUMBER “Days of extension”, Determining days till issuance for final EIS means if Tentative or recommended decision will contain a final EIS with The decision, then Never; otherwise, consider the case distinctions of Cause for extension :  when NOTHING has  then Day with Closing date. when JUST has cause then Day with the sum of Closing date and the sum of 45 and Days of extension.

For the purposes of this provision—

“Closing date” means the sum of The decision's Proceeding Record's Closing date and 45;

###### Section 7.3 (b) (3)

<!-- l4: decide:Notice of no significant adverse effect on the environment determination will be filed in accordance with 6 NYCRR 617.10 -->

**25.** In relation to a Tentative or recommended decision “The decision”, Notice of no significant adverse effect on the environment determination will be filed in accordance with 6 NYCRR 617.10 means if The decision's On the basis of the record of the proceeding (including the draft EIS and any comments received thereon), the Administrative Law Judge issuing this decision determined that the action will not have a significant adverse effect on the environment, then TRUE; otherwise, FALSE.

<!-- l4: decide:Copies of the decision (together with a notice of its completion) will be filed in accordance with 6 NYCRR 617.10. -->

**26.** In relation to a Tentative or recommended decision “The decision”, Copies of the decision (together with a notice of its completion) will be filed in accordance with 6 NYCRR 617.10. means if Tentative or recommended decision will contain a final EIS with The decision, then TRUE; otherwise, FALSE.

###### Section 7.3 (c)

<!-- l4: declare:Render decision on whether or not to approve action -->

**27.** In this Act, “Render decision on whether or not to approve action” means a record consisting of—

    (a) “Action”, being an Action that may have a significant adverse effect on the environment.

<!-- l4: decide:Rendering of the decision on whether or not to approve action proposed by applicant -->

**28.** In relation to an Action that may have a significant adverse effect on the environment “The action” and a BOOLEAN “Good cause to delay”, Rendering of the decision on whether or not to approve action proposed by applicant means if Good cause to delay, then FULFILLED; otherwise, consider the case distinctions of The action's EIS's Final filing date :  when NOTHING has  then FULFILLED. when JUST has date then party Commission must Render decision on whether or not to approve action has is exactly The action within the sum of Day with date and 30.

<!-- l4: decide:Never -->

**29.** Never means -1.

<!-- tnr-coverage: 29 provisions; 0 boolean atoms inlined; 5 directives suppressed -->
