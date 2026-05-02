public with sharing class AF_CancelTestDrive {

    public class Input {
        @InvocableVariable(required=true description='Test Drive record Id (String)')
        public String testDriveId;
    }

    public class Output {
        @InvocableVariable(description='True if cancellation succeeded')
        public Boolean success;

        @InvocableVariable(description='Test Drive record Id')
        public String testDriveId;

        @InvocableVariable(description='Test Drive booking number (Name)')
        public String testDriveName;

        @InvocableVariable(description='New status after action')
        public String newStatus;

        @InvocableVariable(description='Message for the agent')
        public String message;
    }

    @InvocableMethod(
        label='Cancel Test Drive'
        description='Cancels a scheduled Test Drive by setting Status__c = Cancelled. Only allowed when current status is Scheduled.'
    )
    public static List<Output> cancel(List<Input> requests) {
        Output out = new Output();
        out.success = false;

        if (requests == null || requests.isEmpty() || String.isBlank(requests[0].testDriveId)) {
            out.message = 'Test Drive Id is missing.';
            return new List<Output>{ out };
        }

        Id tdId;
        try {
            tdId = (Id)requests[0].testDriveId;
        } catch (Exception e) {
            out.message = 'Invalid Test Drive Id format.';
            return new List<Output>{ out };
        }

        Test_Drive__c td = [
            SELECT Id, Name, Status__c
            FROM Test_Drive__c
            WHERE Id = :tdId
            LIMIT 1
        ];

        out.testDriveId = String.valueOf(td.Id);
        out.testDriveName = td.Name;

        if (td.Status__c != 'Scheduled') {
            out.message = 'Only Scheduled bookings can be cancelled. Current status is: ' + td.Status__c;
            out.newStatus = td.Status__c;
            return new List<Output>{ out };
        }

        td.Status__c = 'Cancelled';
        update td;

        out.success = true;
        out.newStatus = 'Cancelled';
        out.message = 'Booking cancelled successfully.';
        return new List<Output>{ out };
    }
}