import { LightningElement, api } from 'lwc';

export default class TestDriveBooking extends LightningElement {
    @api carImageUrl = 'https://via.placeholder.com/500x300';
    @api qrCodeUrl = 'https://via.placeholder.com/150';
    @api phoneNumber = '+91-XXXXXXXXXX';

    handleAI() {
        alert('AI Booking Clicked');
    }

    handleWhatsApp() {
        alert('WhatsApp Clicked');
    }

    handleForm() {
        alert('Form Clicked');
    }
}
