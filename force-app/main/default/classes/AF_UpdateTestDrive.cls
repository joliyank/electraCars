public with sharing class AF_UpdateTestDrive {

    // ===== INPUT =====
    public class Input {
        @InvocableVariable(required=true description='Test Drive record Id (String)')
        public String testDriveId;

        @InvocableVariable(required=false description='New test drive date/time (for reschedule)')
        public Datetime newTestDriveDateTime;

        @InvocableVariable(required=false description='New Dealer Account Id (String)')
        public String dealerId;

        @InvocableVariable(required=false description='New Vehicle Id (String)')
        public String vehicleId;

        @InvocableVariable(required=false description='New location: Doorstep or Dealership')
        public String testDriveLocation;

        @InvocableVariable(required=false description='New doorstep address (required if Doorstep)')
        public String doorstepAddress;

        @InvocableVariable(required=false description='ZIP code (optional update)')
        public String zipCode;

        @InvocableVariable(required=false description='Preferred communication channel (WhatsApp, Email, Phone, SMS)')
        public String preferredChannel;

        @InvocableVariable(required=false description='Email address (required if preferredChannel = Email)')
        public String email;
    }

    // ===== OUTPUT =====
    public class Output {
        @InvocableVariable(description='True if update succeeded')
        public Boolean success;

        @InvocableVariable(description='Test Drive record Id')
        public String testDriveId;

        @InvocableVariable(description='Test Drive booking number (Name)')
        public String testDriveName;

        @InvocableVariable(description='Current status after update')
        public String status;

        @InvocableVariable(description='Updated test drive date/time')
        public Datetime testDriveDateTime;

        @InvocableVariable(description='Message for the agent')
        public String message;
    }

    @InvocableMethod(
        label='Update Test Drive'
        description='Updates a Test Drive only when Status__c = Scheduled (reschedule or change details).'
    )
    public static List<Output> updateTestDrive(List<Input> requests) {

        Output out = new Output();
        out.success = false;

        // 1) Validate request
        if (requests == null || requests.isEmpty()) {
            out.message = 'No input received.';
            return new List<Output>{ out };
        }

        Input req = requests[0];
        if (req == null || String.isBlank(req.testDriveId)) {
            out.message = 'Test Drive Id is missing.';
            return new List<Output>{ out };
        }

        // 2) Parse Id
        Id tdId;
        try {
            tdId = (Id) req.testDriveId;
        } catch (Exception e) {
            out.message = 'Invalid Test Drive Id format.';
            return new List<Output>{ out };
        }

        // 3) Load current Test Drive
        Test_Drive__c td = [
            SELECT Id, Name, Status__c, Customer__c,
                   Dealer__c, Vehicle__c,
                   Zip_Code__c, Test_Drive_Date_Time__c,
                   Test_Drive_Location__c, Doorstep_Address__c,
                   Preferred_Communication_Channel__c
            FROM Test_Drive__c
            WHERE Id = :tdId
            LIMIT 1
        ];

        out.testDriveId = String.valueOf(td.Id);
        out.testDriveName = td.Name;
        out.status = td.Status__c;
        out.testDriveDateTime = td.Test_Drive_Date_Time__c;

        // 4) Only Scheduled can be updated
        if (td.Status__c != 'Scheduled') {
            out.message = 'Only Scheduled bookings can be updated. Current status is: ' + td.Status__c;
            return new List<Output>{ out };
        }

        // 5) Determine if anything is actually being updated
        Boolean hasAnyUpdate =
            (req.newTestDriveDateTime != null) ||
            String.isNotBlank(req.dealerId) ||
            String.isNotBlank(req.vehicleId) ||
            String.isNotBlank(req.testDriveLocation) ||
            String.isNotBlank(req.doorstepAddress) ||
            String.isNotBlank(req.zipCode) ||
            String.isNotBlank(req.preferredChannel) ||
            String.isNotBlank(req.email);

        if (!hasAnyUpdate) {
            out.message = 'No update values were provided.';
            return new List<Output>{ out };
        }

        // 6) Optional Id parsing for dealer/vehicle
        if (String.isNotBlank(req.dealerId)) {
            try {
                td.Dealer__c = (Id) req.dealerId;
            } catch (Exception e) {
                out.message = 'Invalid dealerId format.';
                return new List<Output>{ out };
            }
        }

        if (String.isNotBlank(req.vehicleId)) {
            try {
                td.Vehicle__c = (Id) req.vehicleId;
            } catch (Exception e) {
                out.message = 'Invalid vehicleId format.';
                return new List<Output>{ out };
            }
        }

        // 7) Apply updates
        if (req.newTestDriveDateTime != null) {
            td.Test_Drive_Date_Time__c = req.newTestDriveDateTime;
        }

        if (String.isNotBlank(req.zipCode)) {
            td.Zip_Code__c = req.zipCode.trim();
        }

        if (String.isNotBlank(req.testDriveLocation)) {
            td.Test_Drive_Location__c = req.testDriveLocation.trim();
        }

        if (String.isNotBlank(req.preferredChannel)) {
            td.Preferred_Communication_Channel__c = req.preferredChannel.trim();
        }

        // 8) Doorstep validation: if location is Doorstep, ensure address exists
        String effectiveLoc = String.isNotBlank(req.testDriveLocation)
            ? req.testDriveLocation
            : td.Test_Drive_Location__c;

        String locLower = (effectiveLoc == null) ? '' : effectiveLoc.trim().toLowerCase();
        Boolean isDoorstep = (locLower == 'doorstep' || locLower == 'door' || locLower == 'home');

        if (isDoorstep) {
            if (String.isNotBlank(req.doorstepAddress)) {
                td.Doorstep_Address__c = req.doorstepAddress;
            }
            if (String.isBlank(td.Doorstep_Address__c)) {
                out.message = 'Doorstep address is required for Doorstep test drive.';
                return new List<Output>{ out };
            }
        } else {
            // If user explicitly changed location away from Doorstep, clear address
            if (String.isNotBlank(req.testDriveLocation)) {
                td.Doorstep_Address__c = null;
            }
        }

        // 9) If preferredChannel is Email, ensure email exists (new or existing Person Account email)
        Account personAcc = null;
        if (td.Customer__c != null && (String.isNotBlank(req.email) || (String.isNotBlank(req.preferredChannel) && req.preferredChannel.trim().equalsIgnoreCase('Email')))) {
            personAcc = [
                SELECT Id, PersonEmail
                FROM Account
                WHERE Id = :td.Customer__c
                LIMIT 1
            ];
        }

        if (String.isNotBlank(req.preferredChannel) && req.preferredChannel.trim().equalsIgnoreCase('Email')) {
            String effectiveEmail = String.isNotBlank(req.email)
                ? req.email.trim()
                : (personAcc == null ? null : personAcc.PersonEmail);

            if (String.isBlank(effectiveEmail)) {
                out.message = 'Email address is required when preferred channel is Email.';
                return new List<Output>{ out };
            }
        }

        // 10) Optional: update PersonEmail if email provided
        if (personAcc != null && String.isNotBlank(req.email)) {
            personAcc.PersonEmail = req.email.trim();
            update personAcc;
        }

        // 11) Update Test Drive
        update td;

        // 12) Return updated snapshot
        Test_Drive__c td2 = [
            SELECT Id, Name, Status__c, Test_Drive_Date_Time__c
            FROM Test_Drive__c
            WHERE Id = :td.Id
            LIMIT 1
        ];

        out.success = true;
        out.status = td2.Status__c;
        out.testDriveName = td2.Name;
        out.testDriveDateTime = td2.Test_Drive_Date_Time__c;
        out.message = 'Booking updated successfully.';
        return new List<Output>{ out };
    }
}