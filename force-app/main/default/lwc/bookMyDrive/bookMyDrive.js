import { LightningElement, api } from 'lwc';
import DEFAULT_CAR from '@salesforce/resourceUrl/bmd_car2';
import DEFAULT_QR from '@salesforce/resourceUrl/bmd_qr';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import CAR1 from '@salesforce/resourceUrl/bmd_car_top1';
import CAR2 from '@salesforce/resourceUrl/bmd_car_top2';
import CAR3 from '@salesforce/resourceUrl/bmd_car_top3';
import CAR4 from '@salesforce/resourceUrl/bmd_car_top4';
import CAR5 from '@salesforce/resourceUrl/bmd_car_top5';
import CAR6 from '@salesforce/resourceUrl/bmd_car_top6';
import CAR7 from '@salesforce/resourceUrl/bmd_car_top7';

import AI_STATIC from '@salesforce/resourceUrl/bmd_icon_ai_static';
import WA_STATIC from '@salesforce/resourceUrl/bmd_icon_whatsapp_static';
import FORM_STATIC from '@salesforce/resourceUrl/bmd_icon_form_static';

import ICON_QUICK from '@salesforce/resourceUrl/bmd_icon_quick';
import ICON_SLOT from '@salesforce/resourceUrl/bmd_icon_slot';
import ICON_NO_OBLIGATION from '@salesforce/resourceUrl/bmd_icon_no_obligation';

import CONFIRM_IMG from '@salesforce/resourceUrl/CONFIRM_IMG';

import findDealerByZip from '@salesforce/apex/BookMyDriveController.findDealerByZip';
import findCustomerByMobile from '@salesforce/apex/BookMyDriveController.findCustomerByMobile';
import createBooking from '@salesforce/apex/BookMyDriveController.createBooking';

export default class BookMyDrive extends LightningElement {
    @api carImageUrl;
    @api qrCodeUrl;
    @api phoneNumber;
    isZipLoading = false;
    isMobileLoading = false;
    isConfirmed = false;

    // ===== UI State =====
    isAiOpen = false;
    isQrZoomOpen = false;

    // Transform origin (relative to .bmd-stage)
    originX = 0;
    originY = 0;

    // Focus restore
    lastFocusedElement;

    // Carousel
    disableSlideTransition = false;
    activeIndex = 0;
    _timer = null;
    _wired = false;
    
    isChatReady = false;
    _poller;
    bookingRequest = [];

    // carsBase = [
    //     { id: '1', name: 'Sierra', img: CAR1 },
    //     { id: '2', name: 'Harrier', img: CAR2 },
    //     { id: '3', name: 'Punch', img: CAR5 },
    //     { id: '4', name: 'Safari', img: CAR3 },
    //     { id: '5', name: 'Nexon', img: CAR4 },
    //     { id: '6', name: 'Safari', img: CAR6 },
    //     { id: '7', name: 'Nexon', img: CAR7 }        
    // ];

    carsBase = [
        { id: '1', name: 'Car X+', img: CAR3 },
        { id: '2', name: 'Car YZ', img: CAR4 },
        { id: '3', name: 'Car Z+', img: CAR6 },
        { id: '4', name: 'Car ZX', img: CAR7 }       
    ];

    isFormOpen = false;

    formData = {
        name: '',
        mobile: '',
        email: '',
        zip: '',
        carModel: '',
        fuelType: 'Petrol',
        datetime: '',
        address: '',
        communication: '',
        locationType: 'SHOWROOM'
    };

    // ===== Progressive form state =====
    dealerLookupInProgress = false;
    customerLookupInProgress = false;

    zipErrorMsg = '';
    dealerFound = false;
    dealerId = null;
    dealerName = '';
    dealerShowroomAddress = '';

    mobileErrorMsg = '';
    customerFound = false;
    mobileInfoMsg = '';

    messages = [];
    currentMessage = '';
    lastUserMessage = '';
    botReply = '';
    messageCounter = 0;
    customerAcc;
    avlVehicleList;

    // ===== Coachmark state (Start Chat guidance) =====
    isChatCoachmarkOpen = false;
    _coachTimer;
    _ignoreDocClickUntil = 0;
    _docClickHandler;
    testDriveName;

    get confirmImage() {
        return CONFIRM_IMG;
    }

    get formModalClass() {
        return this.isFormOpen ? 'bmd-formModal bmd-formModal--open' : 'bmd-formModal';
    }

    get isDoorstep() {
        return this.formData.locationType === 'DOOR';
    }

    get isShowroom() {
        return this.formData.locationType === 'SHOWROOM';
      }

    get nearestShowroom() {
        return this.dealerShowroomAddress || '—';
    }

    get formModalStyle() {
        const x = this.originX || 0;
        const y = this.originY || 0;

        return `transform-origin: ${x}px ${y}px;`;
    }

    // ===== Existing getters =====
    get aiIconStatic() { return AI_STATIC; }
    get waIconStatic() { return WA_STATIC; }
    get formIconStatic() { return FORM_STATIC; }

    get featureQuickIcon() { return ICON_QUICK; }
    get featureSlotIcon() { return ICON_SLOT; }
    get featureNoObligationIcon() { return ICON_NO_OBLIGATION; }


    get carSrc() {
        return this.isNonEmpty(this.carImageUrl) ? this.carImageUrl.trim() : DEFAULT_CAR;
    }

    get qrSrc() {
        return this.isNonEmpty(this.qrCodeUrl) ? this.qrCodeUrl.trim() : DEFAULT_QR;
    }

    get displayPhone() {
        return this.isNonEmpty(this.phoneNumber) ? this.phoneNumber.trim() : '+1 415 523 8886';
    }

    get visibleIndex() {
        const total = (this.carsBase || []).length;
        if (!total) return 0;
        return this.activeIndex === total ? 0 : this.activeIndex;
    }

    get carsWithDots() {
        return (this.carsBase || []).map((c, idx) => ({
            ...c,
            dotClass: idx === this.visibleIndex ? 'bmd-dot bmd-dot--active' : 'bmd-dot',
            dotAriaLabel: `Show ${c.name}`
        }));
    }

    get loopCars() {
        const base = this.carsBase || [];
        if (!base.length) return [];
        const withKeys = base.map((c) => ({ ...c, key: `${c.id}-base` }));
        const cloneFirst = { ...base[0], key: `${base[0].id}-clone` };
        return [...withKeys, cloneFirst];
    }

    get slidesStyle() {
        return `
            transform: translate3d(-${this.activeIndex * 100}%, 0, 0);
            ${this.disableSlideTransition ? 'transition: none !important;' : ''}
        `;
    }

    // ===== Modal classes =====

    get aiModalClass() {
        return this.isAiOpen ? 'bmd-aiModal bmd-aiModal--open' : 'bmd-aiModal';
    }

    get aiModalStyle() {
        const x = this.originX || 0;
        const y = this.originY || 0;
        return `transform-origin: ${x}px ${y}px; --bmd-origin-x: ${x}px; --bmd-origin-y: ${y}px;`;
    }

    get qrBackdropClass() {
        return this.isQrZoomOpen ? 'bmd-qrBackdrop bmd-qrBackdrop--open' : 'bmd-qrBackdrop';
    }

    get qrModalClass() {
        return this.isQrZoomOpen ? 'bmd-qrModal bmd-qrModal--open' : 'bmd-qrModal';
    }

    isBlank(v) {
        return v === null || v === undefined || String(v).trim().length === 0;
    }
      
    get isSubmitDisabled() {
        // Don’t allow submit before the details step is open
        if (!this.showDetailsStep) return true;
      
        // Must have a valid dealer from zip
        if (!this.dealerFound) return true;
      
        // Mobile must be 10 digits
        const mob = String(this.formData.mobile || '').replace(/[^0-9]/g, '');
        if (mob.length !== 10) return true;
      
        // Manual/Prefilled name & email must be present
        if (this.isBlank(this.formData.name)) return true;
        if (this.isBlank(this.formData.email)) return true;
      
        // Booking details
        if (this.isBlank(this.formData.carModel)) return true;
        if (this.isBlank(this.formData.fuelType)) return true;
        if (this.isBlank(this.formData.datetime)) return true;
        if (this.isBlank(this.formData.communication)) return true;
      
        // Doorstep address is mandatory only when locationType is DOOR
        if (this.formData.locationType === 'DOOR' && this.isBlank(this.formData.address)) return true;
        this.bookingRequest = {
                name: this.formData.name,
                mobile: this.formData.mobile,
                email: this.formData.email,
                zip: this.formData.zip,
                carModel: this.formData.carModel,
                fuelType: this.formData.fuelType,
                timeSlot: this.formData.datetime,
                address: this.formData.address,
                communication: this.formData.communication,
                locationType: this.formData.locationType,
                dealerId: this.dealerId
            };
        return false;
    }

    // ===== Lifecycle =====
    connectedCallback() {
        this.preloadCars().then(() => {
            this.startCarousel();
        });

        // Close coachmark on ANY click in the page (including the embedded chat bubble click)
        this._docClickHandler = this.handleDocClickCapture.bind(this);
        window.addEventListener('click', this._docClickHandler, true); // capture phase

    }

    disconnectedCallback() {
        this.stopCarousel();
        
        if (this._poller) {
            window.clearInterval(this._poller);
            this._poller = null;
        }

        
        if (this._docClickHandler) {
            window.removeEventListener('click', this._docClickHandler, true);
            this._docClickHandler = null;
        }
        window.clearTimeout(this._coachTimer);
        this._coachTimer = null;

    }

    renderedCallback() {
        if (this._wired) return;
        this._wired = true;

        const track = this.template.querySelector('.bmd-slides');
        if (track) {
            track.addEventListener('transitionend', () => {
                const total = this.carsBase.length;

                if (this.activeIndex === total) {
                    // STEP 1: disable transition
                    this.disableSlideTransition = true;

                    // STEP 2: jump to first slide
                    this.activeIndex = 0;

                    // STEP 3: wait 2 frames (CRITICAL)
                    requestAnimationFrame(() => {
                        requestAnimationFrame(() => {
                            this.disableSlideTransition = false;
                        });
                    });
                }
            });
        }
    }

    // ===== Carousel controls =====
    startCarousel() {
        this.stopCarousel();
        const total = (this.carsBase || []).length;
        if (!total) return;

        this._timer = setInterval(() => {
            const total = this.carsBase.length;

            if (this.activeIndex < total) {
                this.activeIndex += 1;
            }
        }, 3000);
    }

    stopCarousel() {
        if (this._timer) {
            window.clearInterval(this._timer);
            this._timer = null;
        }
    }

    pauseCarousel() {
        this.stopCarousel();
    }

    resumeCarousel() {
        this.startCarousel();
    }

    handleDotClick(event) {
        event.stopPropagation();
        const idx = Number(event.currentTarget?.dataset?.index);
        if (Number.isNaN(idx)) return;

        this.disableSlideTransition = false;
        this.activeIndex = idx;
        this.startCarousel();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleBookFromCar(event) {
        event.stopPropagation();
        const id = event.currentTarget?.dataset?.id;
        this.openAiFromElement(event.currentTarget, id);
    }

    // ===== AI Modal =====
    openAiFromElement(el, carId) {
        this.selectedCar = (this.carsBase || []).find((c) => c.id === carId);
        this.setOriginFromElement(el);
        this.isAiOpen = true;
    }

    get disableStartChat() {
        return !this.isChatReady;
    }

    //OLD METHOD - handleStartChat
    handleStartChat(event) {
        console.log('@@ : AI Start Chat Clicked');
    
        // 1) Show the dim + arrow guidance
        this.showChatCoachmark();
    
        // 2) ALSO attempt programmatic launch (if available) via your head markup listener
        // (Safe: even if it fails, the coachmark still helps the user click the bubble)
        try {
            document.dispatchEvent(new CustomEvent('miaw:launch'));
        } catch (e) {
            // no-op
        }
    }

    showChatCoachmark() {
        // prevent the same click (Start Chat) from immediately closing it
        this._ignoreDocClickUntil = Date.now() + 250;
    
        //this.isChatCoachmarkOpen = true;
    
        // auto-close after 5s
        window.clearTimeout(this._coachTimer);
        this._coachTimer = window.setTimeout(() => {
            this.hideChatCoachmark();
        }, 5000);
    }
    
    hideChatCoachmark() {
        this.isChatCoachmarkOpen = false;
        window.clearTimeout(this._coachTimer);
        this._coachTimer = null;
    }
    
    handleDocClickCapture() {
        if (!this.isChatCoachmarkOpen) return;
    
        // ignore the initial Start Chat click
        if (Date.now() < this._ignoreDocClickUntil) return;
    
        // requirement: click anywhere should close it
        this.hideChatCoachmark();
    }
    

    initializeChat() {
        const greeting = '👋 Hi! How can i help you today ?';

        this.messages = [
            {
                id: this.generateMsgId(),
                text: greeting,
                type: 'bot',
                rowClass: 'bmd-chatRow bot',
                bubbleClass: 'bmd-chatBubble bot'
            }
        ];
    }

    handleMessageChange(event) {
        this.currentMessage = event.target.value;
    }

    handleCloseAi() {
        this.isAiOpen = false;

        window.clearTimeout(this._restoreFocusTimer);
        this._restoreFocusTimer = window.setTimeout(() => {
            if (this.lastFocusedElement && typeof this.lastFocusedElement.focus === 'function') {
                this.lastFocusedElement.focus();
            }
        }, 0);
    }

    handleAiKeydown(event) {
        if (!event) return;
        if (event.key === 'Escape') {
            this.handleCloseAi();
            return;
        }
        if (event.key === 'Enter') {
            this.handleSendMessage();
        }
    }

    handleSendMessage() {
        if (!this.currentMessage || !this.currentMessage.trim()) return;

        const userMsg = this.currentMessage.trim();

        // 1. store user message (for Apex later)
        this.lastUserMessage = userMsg;

        // 2. push user message to UI
        this.messages = [
            ...this.messages,
            {
                id: this.generateMsgId(),
                text: userMsg,
                type: 'user',
                rowClass: 'bmd-chatRow user',
                bubbleClass: 'bmd-chatBubble user'
            }
        ];

        // 3. clear input
        this.currentMessage = '';

        // 4. simulate bot response (later Apex)
        this.handleBotResponse('Got it 👍 Let me check available slots...');

        ////replace above handleBotResponse call with below code:
        //const response = await callApex(this.lastUserMessage);
        //this.handleBotResponse(response);
    }

    handleBotResponse(responseText) {
        this.botReply = responseText;

        this.messages = [
            ...this.messages,
            {
                id: this.generateMsgId(),
                text: responseText,
                type: 'bot',
                rowClass: 'bmd-chatRow bot',
                bubbleClass: 'bmd-chatBubble bot'
            }
        ];
        setTimeout(() => {
            const container = this.template.querySelector('.bmd-aiBody');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 0);
    }

    generateMsgId() {
        this.messageCounter += 1;
        return 'msg-' + this.messageCounter;
    }

    // ===== QR Zoom =====
    handleOpenQrZoom() {
        this.isQrZoomOpen = true;
    }

    handleCloseQrZoom() {
        this.isQrZoomOpen = false;
    }

    handleQrKeydown(event) {
        if (!event) return;
        if (event.key === 'Escape') {
            this.handleCloseQrZoom();
        }
    }

    handleQrFrameKeydown(event) {
        if (!event) return;
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleOpenQrZoom();
        }
    }

    // ===== WhatsApp =====
    handleWhatsApp() {
        this.dispatchEvent(new CustomEvent('whatsappclick'));
    
        const digits = this.normalizePhoneToDigits(this.displayPhone);
        const msg = 'Hi Team, i need to book a test drive !!';
        const encodedMsg = encodeURIComponent(msg);
        const waLink = `https://wa.me/${digits}?text=${encodedMsg}`;
    
        const isMobile = window.matchMedia('(max-width: 980px)').matches;
        if (isMobile) {
            window.location.href = `whatsapp://send?phone=${digits}&text=${encodedMsg}`;
            setTimeout(() => window.location.href = waLink, 800);
        } else {
            window.open(waLink, '_blank');
        }
    }

    handleForm(event) {
        this.dispatchEvent(new CustomEvent('formclick'));

        this.lastFocusedElement = event?.currentTarget;
        this.setOriginFromElement(event?.currentTarget);

        this.isFormOpen = true;
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
      
        // Route Zip/Mobile through progressive flow (do not break other fields)
        if (field === 'zip') {
          value = String(value || '').replace(/[^0-9]/g, '').slice(0, 6);
          this.formData = { ...this.formData, zip: value };
          this.handleZipChanged(value);
          return;
        }
      
        if (field === 'mobile') {
          value = String(value || '').replace(/[^0-9]/g, '').slice(0, 10);
          this.formData = { ...this.formData, mobile: value };
          this.handleMobileChanged(value);
          return;
        }
      
        // Capture date and time for datetime field
        if (field === 'datetime') {
          // Store the datetime-local input value in formData.datetime
          this.formData = {
            ...this.formData,
            datetime: value
          };
          return;
        }
      
        // Existing behavior for remaining fields
        this.formData = {
          ...this.formData,
          [field]: value
        };
        console.log('this.formData'+JSON.stringify(this.formData));
    }

    handleZipChanged(zipVal) {
        // Reset downstream steps when zip changes
        this.zipErrorMsg = '';
        this.dealerFound = false;
        this.dealerName = '';
        this.dealerShowroomAddress = '';
        this.showMobileStep = false;
        this.showDetailsStep = false;
      
        // Also reset customer info if zip changes
        this.mobileErrorMsg = '';
        this.customerFound = false;
        this.customerName = '';
        this.customerEmail = '';
        this.nameEmailReadonly = false;
      
        // If not 6 digits, stop
        if (!zipVal || zipVal.length !== 6) return;
      
        window.clearTimeout(this._zipTimer);
        this._zipTimer = window.setTimeout(() => {
          this.lookupDealer(zipVal);
        }, 350);
    }
      
    async lookupDealer(zipVal) {
        this.dealerLookupInProgress = true;
        this.zipErrorMsg = '';
      
        try {
            this.isZipLoading = true;
            const res = await findDealerByZip({ zip: zipVal });
      
            if (res && res.found) {
                this.dealerFound = true;
                this.dealerId = res.dealerId;
                this.dealerName = res.dealerName;
                this.dealerShowroomAddress = res.showroomAddress;
                this.showMobileStep = true;     // unlock mobile step
                this.avlVehicleList = res.vehiclesList;
            } else {
                this.dealerFound = false;
                this.zipErrorMsg = (res && res.message) ? res.message : 'Sorry, we are not currently available in this zip code.';
            }
        } catch (e) {
            this.dealerFound = false;
            this.zipErrorMsg = (e && e.body && e.body.message) ? e.body.message : 'Unable to validate zip right now.';
        } finally {
            this.dealerLookupInProgress = false;
            this.isZipLoading = false;
        }
    }
    
    handleMobileChanged(mobileVal) {
        // Reset customer + details step when mobile changes
        this.mobileErrorMsg = '';
        this.customerFound = false;
        this.customerName = '';
        this.customerEmail = '';
        this.nameEmailReadonly = false;
        this.showDetailsStep = false;
        this.mobileInfoMsg = '';
      
        // Only proceed after dealer is validated
        if (!this.dealerFound) return;
      
        // If not 10 digits, stop
        if (!mobileVal || mobileVal.length !== 10) return;
      
        window.clearTimeout(this._mobileTimer);
        this._mobileTimer = window.setTimeout(() => {
          this.lookupCustomer(mobileVal);
        }, 350);
    }
      
    async lookupCustomer(mobileVal) {
        this.customerLookupInProgress = true;
        this.mobileErrorMsg = '';
      
        try {
            this.isMobileLoading = true;
            const res = await findCustomerByMobile({ mobile: mobileVal });
      
            if (res && res.found) {
                this.customerFound = true;
                this.customerName = res.name;
                this.customerEmail = res.email;
                this.customerAcc   = res.personAccountId;
        
                // Prefill + lock name/email (user can still edit if you want later)
                this.formData = {
                    ...this.formData,
                    name: res.name || '',
                    email: res.email || ''
                };
                this.nameEmailReadonly = true;
            } else {
                // Manual entry allowed (as per your answer)
                this.customerFound = false;
                this.mobileErrorMsg = ''; // keep errors only for validation/system failures
                this.mobileInfoMsg = 'Kindly fill below details to proceed.';
                this.nameEmailReadonly = false;
        
                // Keep values empty for manual entry
                this.formData = {
                    ...this.formData,
                    name: '',
                    email: ''
                };
            }
        
            // Unlock remaining booking fields regardless of customer found
            this.showDetailsStep = true;
      
        } catch (e) {
            this.customerFound = false;
            this.nameEmailReadonly = false;
            this.showDetailsStep = true; // allow manual path even on lookup error
            this.mobileErrorMsg = (e && e.body && e.body.message) ? e.body.message : 'Unable to validate mobile right now.';
        } finally {
            this.customerLookupInProgress = false;
            this.isMobileLoading = false;
        }
    }
    
    handleLocationChange(event) {
        const value = event.target.value;

        this.formData = {
            ...this.formData,
            locationType: value
        };
    }

    resetFormState() {
        this.formData = {
            zip: null,
            mobile: null,
            dealer: null,
            customer: null
        };

        this.showMobileStep = false;
        this.showDetailsStep = false;
        this.dealerFound = false;
        this.isZipLoading = false;
        this.isMobileLoading = false;
        this.isFormValid = false;
        this.mobileErrorMsg = false;
        this.mobileInfoMsg = false;
        this.isConfirmed = false;
        this.zipErrorMsg = '';

        clearTimeout(this.zipTimeout);
        clearTimeout(this.mobileTimeout);
    }

    handleCloseForm() {
        this.isFormOpen = false;
        this.resetFormState();
        window.setTimeout(() => {
            if (this.lastFocusedElement) {
                this.lastFocusedElement.focus();
            }
        }, 0);
    }

    handleFormKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCloseForm();
        }
    }

    handleSubmitForm() {
        
        console.log('Form Data:', JSON.stringify(this.formData));

            console.log('Submitting booking:', JSON.stringify(this.bookingRequest));

        createBooking({
            requestMap: JSON.stringify(this.bookingRequest)
        })
        .then(result => {
            console.log('Booking created successfully!'); 
            let res = result;
            if(res.success == false){
                // alert('Booking failed: ' + res.message);
                this.showGenericErrorToastMsg('Error',res.message,'error');
                return;
            }            
            // Show confirmation screen
            this.testDriveName = res.testDriveName;
            this.isConfirmed = true;
        })
        .catch(error => {
            console.error('Booking failed:', result.message);
            alert('Booking failed: ' + result.message);
        });
    }

    get backdropClass() {
        return (this.isAiOpen || this.isFormOpen)
            ? 'bmd-backdrop bmd-backdrop--open'
            : 'bmd-backdrop';
    }

    handleBackdropClick() {
        if (this.isAiOpen) this.handleCloseAi();
        if (this.isFormOpen) this.handleCloseForm();
    }
    // ===== Helpers =====
    preloadCars() {
        const urls = (this.carsBase || []).map((c) => c.img);
        if (!urls.length) return Promise.resolve();

        const loaders = urls.map(
            (src) =>
                new Promise((resolve) => {
                    const img = new Image();
                    img.onload = () => resolve(true);
                    img.onerror = () => resolve(false);
                    img.src = src;
                })
        );

        return Promise.all(loaders).then(() => true);
    }

    setOriginFromElement(el) {
        try {
            const stage = this.template.querySelector('.bmd-stage');
            if (!stage || !el) {
                this.originX = 0;
                this.originY = 0;
                return;
            }
            const stageRect = stage.getBoundingClientRect();
            const elRect = el.getBoundingClientRect();
            const x = elRect.left + elRect.width / 2 - stageRect.left;
            const y = elRect.top + elRect.height / 2 - stageRect.top;

            this.originX = Math.max(0, Math.min(stageRect.width, x));
            this.originY = Math.max(0, Math.min(stageRect.height, y));
        } catch (e) {
            this.originX = 0;
            this.originY = 0;
        }
    }

    normalizePhoneToDigits(val) {
        return String(val || '').replace(/\D/g, '');
    }

    isNonEmpty(val) {
        return val !== null && val !== undefined && String(val).trim().length > 0;
    }

    showGenericErrorToastMsg(titleType, errorMsg, variantType) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: titleType,
                message: errorMsg,
                variant: variantType,
                mode: 'dismissable'
            })
        );
    }
}