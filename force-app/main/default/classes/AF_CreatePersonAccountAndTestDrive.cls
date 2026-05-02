public with sharing class AF_CreatePersonAccountAndTestDrive {

    // ===== INPUT =====
    public class Input {
        @InvocableVariable(required=true description='Lead Id returned from Find or Create Lead by Mobile (String)')
        public String leadId;

        @InvocableVariable(required=true description='Customer mobile number (digits preferred)')
        public String mobileNumber;

        @InvocableVariable(required=true description='ZIP code')
        public String zipCode;

        @InvocableVariable(required=true description='Dealer Account Id (String)')
        public String dealerId;

        @InvocableVariable(required=true description='Vehicle Id (String)')
        public String vehicleId;

        @InvocableVariable(required=true description='Preferred test drive date and time')
        public Datetime testDriveDateTime;

        @InvocableVariable(required=true description='Test drive location: Doorstep or Dealership')
        public String testDriveLocation;

        @InvocableVariable(required=false description='Doorstep address (required if Doorstep)')
        public String doorstepAddress;

        @InvocableVariable(required=true description='Preferred communication channel (WhatsApp, Email, Phone, SMS)')
        public String preferredChannel;

        @InvocableVariable(required=false description='Email address (required if preferredChannel = Email)')
        public String email;
    }

    // ===== OUTPUT =====
    public class Output {
        @InvocableVariable(description='Person Account Id (String)')
        public String personAccountId;

        @InvocableVariable(description='Test Drive record Id (String)')
        public String testDriveId;

        @InvocableVariable(description='Message for the agent')
        public String message;

        @InvocableVariable(description='Test Drive Name/Number (String)')
        public String testDriveName;
    }

    @InvocableMethod(
        label='Create Person Account and Test Drive'
        description='Reuses existing Person Account by mobile (PersonMobilePhone preferred). If none, creates Person Account using Lead name, then creates Test Drive. Returns personAccountId and testDriveId as String.'
    )
    public static List<Output> createTestDrive(List<Input> requests) {

        String corrId = 'AGENT-' + String.valueOf(Crypto.getRandomLong());
        publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'START', 'Invoked', null);

        Output out = new Output();

        if (requests == null || requests.isEmpty()) {
            out.message = 'No input received.';
            return new List<Output>{ out };
        }

        Input req = requests[0];

        // --- Validate and normalize ---
        String mobile = normalizeMobile(req.mobileNumber);
        if (String.isBlank(mobile)) {
            out.message = 'Mobile number is blank/invalid.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        if (String.isBlank(req.leadId)) {
            out.message = 'Lead Id is missing.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        Id leadId;
        try {
            leadId = (Id) req.leadId;
        } catch (Exception e) {
            out.message = 'Invalid Lead Id format.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        Id dealerId;
        Id vehicleId;
        try {
            dealerId = (Id) req.dealerId;
            vehicleId = (Id) req.vehicleId;
        } catch (Exception e) {
            out.message = 'Invalid DealerId/VehicleId format.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        String loc = String.isBlank(req.testDriveLocation) ? '' : req.testDriveLocation.trim().toLowerCase();
        Boolean isDoorstep = (loc == 'doorstep' || loc == 'door' || loc == 'home');

        // Doorstep requires address
        if (isDoorstep && String.isBlank(req.doorstepAddress)) {
            out.message = 'Doorstep address is required for Doorstep test drive.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        // Email requires email
        if (!String.isBlank(req.preferredChannel) && req.preferredChannel.trim().equalsIgnoreCase('Email')
            && String.isBlank(req.email)) {
            out.message = 'Email address is required when preferred channel is Email.';
            publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'FAIL', out.message, null);
            return new List<Output>{ out };
        }

        // --- 1) Lead is source-of-truth for name/email ---
        Lead l = [
            SELECT Id, FirstName, LastName, Email, MobilePhone
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        String leadFullName = buildName(l.FirstName, l.LastName);
        String personLastName = String.isBlank(leadFullName) ? 'Customer' : trim80(leadFullName);

        // --- 2) Find existing Person Account by mobile ---
        List<Account> persons = [
            SELECT Id, PersonMobilePhone, Phone, LastName, PersonEmail, PersonMailingStreet, PersonMailingPostalCode
            FROM Account
            WHERE IsPersonAccount = true
              AND (PersonMobilePhone = :mobile OR Phone = :mobile)
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        Account personAcc;
        Boolean isNew = false;

        if (!persons.isEmpty()) {
            personAcc = persons[0];
        } else {
            isNew = true;
            personAcc = new Account();
            personAcc.RecordTypeId = getPersonAccountRT();
            personAcc.LastName = personLastName;

            // Store mobile in PersonMobilePhone (best practice)
            personAcc.PersonMobilePhone = mobile;
            // Optional: also set Phone for compatibility with other systems
            // personAcc.Phone = mobile;

            // Email preference: explicit email > lead email
            if (String.isNotBlank(req.email)) {
                personAcc.PersonEmail = req.email.trim();
            } else if (String.isNotBlank(l.Email)) {
                personAcc.PersonEmail = l.Email;
            }

            // Doorstep address set before insert (avoid extra update)
            if (isDoorstep) {
                personAcc.PersonMailingStreet = req.doorstepAddress;
                personAcc.PersonMailingPostalCode = req.zipCode;
            }

            insert personAcc;
        }

        // If existing account and Doorstep info provided, update address
        if (!isNew && isDoorstep) {
            personAcc.PersonMailingStreet = req.doorstepAddress;
            personAcc.PersonMailingPostalCode = req.zipCode;
            update personAcc;
        }

        // --- 3) Create Test Drive record ---
        Test_Drive__c td = new Test_Drive__c();
        td.Customer__c = personAcc.Id;
        td.Dealer__c = dealerId;
        td.Vehicle__c = vehicleId;

        // NOTE: If this is Number field, Decimal drops leading zeros.
        // For India 10-digit mobiles, typically no leading zeros, OK.
        td.Mobile_Number__c = Decimal.valueOf(mobile);

        td.Zip_Code__c = req.zipCode;
        td.Test_Drive_Date_Time__c = req.testDriveDateTime;
        td.Test_Drive_Location__c = req.testDriveLocation;
        td.Doorstep_Address__c = isDoorstep ? req.doorstepAddress : null;
        td.Preferred_Communication_Channel__c = req.preferredChannel;
        td.Status__c = 'Scheduled';

        insert td;

        Test_Drive__c tdInserted = [SELECT Id, Name
                                        FROM Test_Drive__c
                                        WHERE Id = :td.Id
                                        LIMIT 1
                                    ];
        out.testDriveName = tdInserted.Name;
        out.personAccountId = String.valueOf(personAcc.Id);
        out.testDriveId = String.valueOf(td.Id);
        out.message = isNew
            ? 'Created new Person Account and created Test Drive.'
            : 'Reused existing Person Account and created Test Drive.';

        publishAudit('AF_CreatePersonAccountAndTestDrive', corrId, 'SUCCESS',
            'personAccountId=' + out.personAccountId + ' testDriveId=' + out.testDriveId, null);

        return new List<Output>{ out };
    }

    // ===== HELPERS =====

    private static String normalizeMobile(String mobile) {
        if (String.isBlank(mobile)) return null;
        String digits = mobile.replaceAll('[^0-9]', '');
        if (digits != null && digits.length() > 10) {
            digits = digits.substring(digits.length() - 10);
        }
        return digits;
    }

    private static String trim80(String s) {
        if (String.isBlank(s)) return s;
        s = s.trim();
        return s.length() > 80 ? s.substring(0, 80) : s;
    }

    private static String buildName(String firstName, String lastName) {
        if (String.isBlank(firstName)) return lastName;
        if (String.isBlank(lastName)) return firstName;
        return firstName + ' ' + lastName;
    }

    private static Id getPersonAccountRT() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND IsPersonType = true
            LIMIT 1
        ].Id;
    }

    private static void publishAudit(String actionName, String corrId, String status, String message, String payload) {
        try {
            Agent_Action_Audit__e evt = new Agent_Action_Audit__e();
            evt.ActionName__c = actionName;
            evt.CorrelationId__c = corrId;
            evt.Status__c = status;
            evt.Message__c = message;
            evt.Payload__c = payload;
            EventBus.publish(evt);
        } catch (Exception ignore) {
            System.debug('@@@ inside catch of publishAudit: ');
            // Never fail business transaction because audit failed
        }
    }
}