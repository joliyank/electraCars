/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : Nand Kishor
**/
public without sharing class BookMyDriveController {

    public static Map<String,Id> idVsVehichleMap = new Map<String,Id>();

    public class DealerResult {
        @AuraEnabled public Boolean found;
        @AuraEnabled public String message;

        @AuraEnabled public Id dealerId;
        @AuraEnabled public String dealerName;
        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public String billingCountry;

        @AuraEnabled public String showroomAddress;
        @AuraEnabled public List<String> vehiclesList;
    }

    public class CustomerResult {
        @AuraEnabled public Boolean found;
        @AuraEnabled public String message;

        @AuraEnabled public Id personAccountId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobilePhone;
        
    }

    @AuraEnabled(cacheable=true)
    public static DealerResult findDealerByZip(String zip) {
        List<String> availVehicle = new List<String>();
        DealerResult res = new DealerResult();
        res.found = false;

        String cleanZip = (zip == null) ? '' : zip.trim();
        // India-only strict 6 digits
        if (!Pattern.matches('^[0-9]{6}$', cleanZip)) {
            res.message = 'Please enter a valid 6 digit zip code.';
            return res;
        }
        System.debug('@@cleanZip >>' + cleanZip );
        // Type = 'Dealer' and BillingPostalCode = entered zip (dealer uniqueness confirmed by you)
        List<Account> dealers = [
            SELECT Id, Name,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE RecordType.Name = 'Business Account'
              AND BillingPostalCode = :cleanZip
            LIMIT 1
        ];

        if (dealers.isEmpty()) {
            res.message = 'Sorry, we are not currently available in this zip code.';
            return res;
        }
        List<Dealer_Vehicle__c > vehicles = [
            SELECT Id, Name,Vehicle__c,Vehicle__r.Name 
            FROM Dealer_Vehicle__c
            WHERE Dealer__c  =:dealers[0].Id
        ];
        for(Dealer_Vehicle__c eachObj:vehicles) {
            System.debug('@@Dealer Vehicle: ' + eachObj.Name);
            availVehicle.add(eachObj.Vehicle__r.Name);
            idVsVehichleMap.put(eachObj.Vehicle__r.Name, eachObj.Vehicle__c);
        }

        Account d = dealers[0];
        res.found = true;
        res.message = 'Dealer found';

        res.dealerId = d.Id;
        res.dealerName = d.Name;
        res.billingStreet = d.BillingStreet;
        res.billingCity = d.BillingCity;
        res.billingState = d.BillingState;
        res.billingPostalCode = d.BillingPostalCode;
        res.billingCountry = d.BillingCountry;
        res.vehiclesList = availVehicle;

        // Prebuild a single showroom string so LWC can show it immediately
        List<String> parts = new List<String>();
        if (String.isNotBlank(d.BillingStreet)) parts.add(d.BillingStreet);
        if (String.isNotBlank(d.BillingCity)) parts.add(d.BillingCity);
        if (String.isNotBlank(d.BillingState)) parts.add(d.BillingState);
        if (String.isNotBlank(d.BillingPostalCode)) parts.add(d.BillingPostalCode);
        if (String.isNotBlank(d.BillingCountry)) parts.add(d.BillingCountry);
        res.showroomAddress = String.join(parts, ', ');

        return res;
    }

    @AuraEnabled(cacheable=true)
    public static CustomerResult findCustomerByMobile(String mobile) {
        CustomerResult res = new CustomerResult();
        res.found = false;

        String cleanMobile = (mobile == null) ? '' : mobile.replaceAll('[^0-9]', '');
        // Strict 10 digits
        if (!Pattern.matches('^[0-9]{10}$', cleanMobile)) {
            res.message = 'Please enter a valid 10 digit mobile number.';
            return res;
        }
        System.debug('@@cleanMobile >>' + cleanMobile);
        // Person Account lookup.
        // NOTE: Many orgs store mobile in PersonMobilePhone; you asked "Phone", but supporting both improves hit rate.
        List<Account> persons = [
            SELECT Id, Name, PersonEmail, Phone, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
              AND (Phone = :cleanMobile OR PersonMobilePhone = :cleanMobile)
            LIMIT 1
        ];

        if (persons.isEmpty()) {
            res.message = 'Customer not found. Please enter name and email manually.';
            return res;
        }

        Account p = persons[0];
        res.found = true;
        res.message = 'Customer found';

        res.personAccountId = p.Id;
        res.name = p.Name;
        res.email = p.PersonEmail;
        res.phone = p.Phone;
        res.mobilePhone = p.PersonMobilePhone;
        System.debug('@@res >>' + res);
        return res;
    }

    public class BookingRequest {
        @AuraEnabled public String name;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
        @AuraEnabled public String zip;
        @AuraEnabled public String carModel;
        @AuraEnabled public String fuelType;
        @AuraEnabled public String timeSlot;
        @AuraEnabled public String address;
        @AuraEnabled public String communication;
        @AuraEnabled public String locationType;
        @AuraEnabled public Id dealerId;
    }

    public class BookingResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id personAccountId;
        @AuraEnabled public Id testDriveId;
        @AuraEnabled public String testDriveName;
    }

    @AuraEnabled
    public static BookingResult createBooking(String requestMap) {
        System.debug('request'+requestMap);
        BookingResult result = new BookingResult();
        result.success = false;
        BookingRequest request = (BookingRequest)JSON.deserialize(requestMap, BookingRequest.class);
        System.debug('@@createBooking request: ' + JSON.serialize(request));
        System.debug('// Validate required fields_'+request.mobile);
        if (String.isBlank(request.name)) {
            result.message = 'Name is required.';
            return result;
        }
        try {
            // Validate input
            if (request == null) {
                result.message = 'Invalid request data.';
                return result;
            }

            String mobile = normalizeMobile(request.mobile);
            if (String.isBlank(mobile)) {
                result.message = 'Mobile number is required.';
                return result;
            }

            // 1️⃣ Find or Create Person Account
            List<Account> persons = [
                SELECT Id, Phone, PersonEmail, LastName
                FROM Account
                WHERE IsPersonAccount = true
                AND Phone = :mobile
                LIMIT 1
            ];

            Account personAcc;
            if (!persons.isEmpty()) {
                personAcc = persons[0];
                // Update name and email if provided
                if (String.isNotBlank(request.name)) {
                    personAcc.LastName = request.name;
                }
                if (String.isNotBlank(request.email)) {
                    personAcc.PersonEmail = request.email;
                }
            } else {
                // Create new Person Account
                personAcc = new Account();
                personAcc.RecordTypeId = getPersonAccountRT();
                personAcc.LastName = String.isNotBlank(request.name) ? request.name : 'Customer';
                personAcc.Phone = mobile;
                personAcc.PersonMobilePhone = mobile;
                if (String.isNotBlank(request.email)) {
                    personAcc.PersonEmail = request.email;
                }
            }

            // 2️⃣ Update address if Doorstep
            if ('DOOR'.equalsIgnoreCase(request.locationType) && String.isNotBlank(request.address)) {
                personAcc.PersonMailingStreet = request.address;
                personAcc.PersonMailingPostalCode = request.zip;
            }

            upsert personAcc;

            for(Dealer_Vehicle__c eachObj:[SELECT Id, Name,Vehicle__c,Vehicle__r.Name FROM Dealer_Vehicle__c WHERE Dealer__c  =:request.dealerId]) {
                idVsVehichleMap.put(eachObj.Vehicle__r.Name, eachObj.Vehicle__c);
            }
            // 4️⃣ Create Test Drive record
            Test_Drive__c td = new Test_Drive__c();
            td.Customer__c = personAcc.Id;
            td.Dealer__c = request.dealerId;
            td.Vehicle__c = idVsVehichleMap.containsKey(request.carModel)? idVsVehichleMap.get(request.carModel) : null;
            td.Mobile_Number__c = Decimal.valueOf(mobile);
            td.Zip_Code__c = request.zip;
            
            // Convert datetime string to Datetime
            if (String.isNotBlank(request.timeSlot)) {
                td.Test_Drive_Date_Time__c = convertToDatetime(request.timeSlot);
            }
            
            td.Test_Drive_Location__c = 'DOOR'.equalsIgnoreCase(request.locationType) ? 'Doorstep' : 'Dealership';
            td.Doorstep_Address__c = request.address;
            td.Preferred_Communication_Channel__c = request.communication;
            td.Status__c = 'Scheduled';

            insert td;

            Test_Drive__c tdInserted = [SELECT Id, Name
                                        FROM Test_Drive__c
                                        WHERE Id = :td.Id
                                        LIMIT 1
                                    ];

            result.testDriveName = tdInserted.Name;
            result.success = true;
            result.message = 'Test drive booked successfully!';
            result.personAccountId = personAcc.Id;
            result.testDriveId = td.Id;

            // 3️⃣ Create new Lead (only when name provided)
            Lead newLead = new Lead();
            newLead.MobilePhone = mobile;
            newLead.LastName =  personAcc.LastName;
            newLead.Company = 'Individual';
            newLead.Status = 'Open - Not Contacted';

            insert newLead;

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error: ' + e.getMessage();
            System.debug('Error creating booking: ' + e.getMessage());
        }

        return result;
    }

    // ===== HELPER METHODS =====

    private static String normalizeMobile(String mobile) {
        return mobile == null ? null : mobile.replaceAll('[^0-9]', '');
    }

    private static Id getPersonAccountRT() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // private static Id findVehicleByModelAndFuel(String model, String fuelType, Id dealerId) {
    //     if (String.isBlank(model) || String.isBlank(fuelType)) {
    //         return null;
    //     }

    //     List<Vehicle> vehicles = [
    //         SELECT Id
    //         FROM Vehicle
    //         WHERE Model__c = :model
    //         AND Fuel_Type__c = :fuelType
    //         AND Dealer__c = :dealerId
    //         AND Status__c = 'Available'
    //         LIMIT 1
    //     ];

    //     return vehicles.isEmpty() ? null : vehicles[0].Id;
    // }

    private static Datetime convertToDatetime(String datetimeStr) {
        try {
            // Convert from HTML datetime-local format (YYYY-MM-DDTHH:mm)
            // to Salesforce Datetime
            return Datetime.valueOfGmt(datetimeStr.replace('T', ' ') + ':00');
        } catch (Exception e) {
            System.debug('Error converting datetime: ' + e.getMessage());
            return null;
        }
    }
}