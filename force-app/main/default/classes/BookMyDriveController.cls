/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-25-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class BookMyDriveController {

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
}