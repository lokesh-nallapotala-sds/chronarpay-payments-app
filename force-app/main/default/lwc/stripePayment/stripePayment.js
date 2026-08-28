import {
    LightningElement,
    api
} from 'lwc';

import createPaymentIntent from '@salesforce/apex/StripeController.createPaymentIntent';
import getStripePublishableKey from '@salesforce/apex/StripeController.getStripePublishableKey';
import getPaymentIntent from '@salesforce/apex/StripeController.getPaymentIntent';

export default class StripePayment extends LightningElement {

    // ---------------------------------------------------------
    // Public properties
    // ---------------------------------------------------------

    @api invoiceNumber;

    @api amount;

    @api currency = 'USD';

    @api customerName;

    @api customerEmail;

    @api description;

    // Accept a JSON string containing an array of invoice objects
    @api invoicesJson;


    // ---------------------------------------------------------
    // Stripe objects
    // ---------------------------------------------------------

    stripe;

    elements;

    paymentElement;

    paymentIntentId;

    clientSecret;


    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    isLoading = true;

    isProcessing = false;

    paymentCompleted = false;

    showPaymentForm = false;

    errorMessage;

    successMessage;

    paymentStatus = 'Pending';


    // ---------------------------------------------------------
    // Internal
    // ---------------------------------------------------------

    stripeJsLoaded = false;

    initialized = false;


    // ---------------------------------------------------------
    // Computed
    // ---------------------------------------------------------

    get formattedAmount() {

        if (
            this.amount === null ||
            this.amount === undefined ||
            this.amount === ''
        ) {
            return '0.00';
        }


        try {

            return new Intl.NumberFormat(
                undefined, {
                    style: 'currency',
                    currency: this.normalizedCurrency
                }
            ).format(
                Number(this.amount)
            );

        } catch (error) {

            return `${this.amount} ${this.normalizedCurrency}`;

        }
    }


    get normalizedCurrency() {

        return (
            this.currency ||
            'USD'
        ).toUpperCase();

    }

    get parsedInvoices() {
        if (!this.invoicesJson) return [];
        try {
            const invs = JSON.parse(this.invoicesJson);
            if (Array.isArray(invs)) return invs;
            return [];
        } catch (err) {
            return [];
        }
    }


    // ---------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------

    async connectedCallback() {

        try {

            await this.initializePayment();

        } catch (error) {

            this.handleError(
                error
            );

        } finally {

            this.isLoading = false;

        }
    }


    // ---------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------

    async initializePayment() {

        this.clearMessages();


        // If invoicesJson provided, derive amount and invoiceNumber from it
        if (this.invoicesJson) {
            try {
                const invs = JSON.parse(this.invoicesJson);
                if (Array.isArray(invs) && invs.length > 0) {
                    // compute sum: pay positive openAmount values, subtract credits
                    let total = 0;
                    invs.forEach(i => {
                        const amt = Number(i.openAmount) || 0;
                        total += amt;
                    });
                    // set amount and invoiceNumber
                    this.amount = total;
                    this.invoiceNumber = invs.map(i => i.billingDocumentNumber).join(', ');
                    this.description = `Payment for invoices: ${this.invoiceNumber}`;
                }
            } catch (err) {
                // ignore parse error, validation will catch missing amount
                console.warn('Could not parse invoicesJson', err);
            }
        }

        this.validateInputs();


        /*
         * Load Stripe.js
         */
        await this.loadStripeJs();


        /*
         * Get publishable key from Salesforce.
         */
        const publishableKey =
            await getStripePublishableKey();


        if (!publishableKey) {

            throw new Error(
                'Stripe publishable key is not configured.'
            );

        }


        /*
         * Initialize Stripe.
         */
        this.stripe =
            window.Stripe(
                publishableKey
            );


        /*
         * Create PaymentIntent through Salesforce.
         */
        const result =
            await createPaymentIntent({

                amount: Number(
                    this.amount
                ),

                currency: this.normalizedCurrency,

                customerName: this.customerName,

                customerEmail: this.customerEmail,

                invoiceNumber: this.invoiceNumber,

                description: this.description,

                paymentId: null,

                accountId: null
            });


        if (!result) {

            throw new Error(
                'Unable to create Stripe PaymentIntent.'
            );

        }


        this.paymentIntentId =
            result.paymentIntentId;


        this.clientSecret =
            result.clientSecret;


        /*
         * Initialize Stripe Payment Element.
         */
        this.initializePaymentElement();

    }


    // ---------------------------------------------------------
    // Stripe.js loading
    // ---------------------------------------------------------

    loadStripeJs() {

        if (
            this.stripeJsLoaded &&
            window.Stripe
        ) {

            return Promise.resolve();

        }


        return new Promise(
            (resolve, reject) => {

                /*
                 * Check whether Stripe.js was already loaded.
                 */
                const existingScript =
                    document.querySelector(
                        'script[data-stripe-js]'
                    );


                if (existingScript) {

                    existingScript.addEventListener(
                        'load',
                        () => {

                            this.stripeJsLoaded =
                                true;

                            resolve();

                        }
                    );


                    existingScript.addEventListener(
                        'error',
                        () => {

                            reject(
                                new Error(
                                    'Unable to load Stripe.js.'
                                )
                            );

                        }
                    );


                    return;
                }


                const script =
                    document.createElement(
                        'script'
                    );


                script.src =
                    'https://js.stripe.com/v3/';


                script.async =
                    true;


                script.dataset.stripeJs =
                    'true';


                script.onload =
                    () => {

                        if (
                            window.Stripe
                        ) {

                            this.stripeJsLoaded =
                                true;

                            resolve();

                        } else {

                            reject(
                                new Error(
                                    'Stripe.js loaded but Stripe object is unavailable.'
                                )
                            );

                        }
                    };


                script.onerror =
                    () => {

                        reject(
                            new Error(
                                'Unable to load Stripe.js.'
                            )
                        );

                    };


                document.head.appendChild(
                    script
                );

            }
        );
    }


    // ---------------------------------------------------------
    // Stripe Payment Element
    // ---------------------------------------------------------

    initializePaymentElement() {

        if (
            !this.stripe ||
            !this.clientSecret
        ) {

            throw new Error(
                'Stripe is not initialized correctly.'
            );

        }


        /*
         * Stripe Elements instance.
         */
        this.elements =
            this.stripe.elements({

                clientSecret: this.clientSecret,

                appearance: {

                    theme: 'stripe',

                    variables: {

                        colorPrimary: '#0176d3',

                        borderRadius: '6px',

                        fontFamily: 'Arial, sans-serif'
                    }
                }
            });


        this.paymentElement =
            this.elements.create(
                'payment'
            );


        /*
         * LWC DOM is not immediately available
         * after connectedCallback.
         */
        requestAnimationFrame(
            () => {

                const container =
                    this.template.querySelector(
                        '.stripe-element'
                    );


                if (!container) {

                    /*
                     * Retry once the template is rendered.
                     */
                    setTimeout(
                        () => {

                            this.mountPaymentElement();

                        },
                        100
                    );

                    return;
                }


                this.mountPaymentElement();

            }
        );
    }


    mountPaymentElement() {

        const container =
            this.template.querySelector(
                '.stripe-element'
            );


        if (
            !container ||
            !this.paymentElement
        ) {

            return;

        }


        /*
         * Prevent duplicate mounting.
         */
        if (
            this.initialized
        ) {

            return;

        }


        this.paymentElement.mount(
            container
        );


        this.initialized =
            true;


        this.showPaymentForm =
            true;

    }


    // ---------------------------------------------------------
    // Pay button
    // ---------------------------------------------------------

    async handlePay() {

        if (
            this.isProcessing
        ) {

            return;

        }


        this.clearMessages();


        if (
            !this.stripe ||
            !this.elements
        ) {

            this.errorMessage =
                'Payment form is not ready.';

            return;

        }


        this.isProcessing =
            true;


        try {

            /*
             * Ask Stripe Elements to validate
             * the payment information.
             */
            const submitResult =
                await this.elements.submit();


            if (
                submitResult.error
            ) {

                throw new Error(
                    submitResult.error.message
                );

            }


            /*
             * Confirm PaymentIntent.
             *
             * Stripe handles the actual payment details.
             */
            const result =
                await this.stripe.confirmPayment({

                    elements: this.elements,

                    clientSecret: this.clientSecret,

                    redirect: 'if_required'
                });


            if (
                result.error
            ) {

                this.paymentStatus =
                    'Failed';


                throw new Error(
                    result.error.message
                );

            }


            /*
             * PaymentIntent confirmation succeeded.
             */
            if (
                result.paymentIntent
            ) {

                this.paymentIntentId =
                    result.paymentIntent.id;


                this.paymentStatus =
                    this.mapStripeStatus(
                        result.paymentIntent.status
                    );


                /*
                 * Important:
                 *
                 * Do NOT mark Salesforce Payment__c as Paid
                 * here.
                 *
                 * The authoritative status comes from the
                 * Stripe webhook.
                 */
                if (
                    result.paymentIntent.status ===
                    'succeeded'
                ) {

                    this.paymentCompleted =
                        true;

                    this.successMessage =
                        'Payment successful.';

                    this.showPaymentForm =
                        false;

                } else if (
                    result.paymentIntent.status ===
                    'processing'
                ) {

                    this.successMessage =
                        'Your payment is being processed.';

                } else {

                    this.successMessage =
                        'Payment submitted successfully.';

                }
            }


        } catch (error) {

            this.handleError(
                error
            );

        } finally {

            this.isProcessing =
                false;

        }
    }


    // ---------------------------------------------------------
    // Status mapping
    // ---------------------------------------------------------

    mapStripeStatus(
        status
    ) {

        switch (
            status
        ) {

            case 'succeeded':
                return 'Paid';

            case 'processing':
                return 'Processing';

            case 'requires_payment_method':
                return 'Pending';

            case 'canceled':
                return 'Canceled';

            default:
                return 'Pending';
        }
    }


    // ---------------------------------------------------------
    // Validation
    // ---------------------------------------------------------

    validateInputs() {

        if (
            this.amount === null ||
            this.amount === undefined ||
            this.amount === ''
        ) {

            throw new Error(
                'Payment amount is required.'
            );

        }


        const numericAmount =
            Number(
                this.amount
            );


        if (
            Number.isNaN(
                numericAmount
            ) ||
            numericAmount <= 0
        ) {

            throw new Error(
                'Payment amount must be greater than zero.'
            );

        }


        if (
            !this.currency
        ) {

            throw new Error(
                'Currency is required.'
            );

        }


        // Customer email and invoiceNumber are recommended but not required when a session
        // provides `invoicesJson`. In that case we've already derived a description.
        if (!this.invoicesJson) {
            if (
                !this.customerEmail
            ) {

                throw new Error(
                    'Customer email is required.'
                );

            }


            if (
                !this.invoiceNumber
            ) {

                throw new Error(
                    'Invoice number is required.'
                );

            }
        }
    }


    // ---------------------------------------------------------
    // Error handling
    // ---------------------------------------------------------

    handleError(
        error
    ) {

        console.error(
            'Stripe payment error',
            error
        );


        let message =
            'Payment could not be processed.';


        if (
            error
        ) {

            if (
                error.body &&
                error.body.message
            ) {

                message =
                    error.body.message;

            } else if (
                error.message
            ) {

                message =
                    error.message;

            } else if (
                error.body &&
                typeof error.body ===
                'string'
            ) {

                message =
                    error.body;

            }
        }


        this.errorMessage =
            message;


        this.paymentStatus =
            'Failed';
    }


    // ---------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------

    clearMessages() {

        this.errorMessage =
            null;

        this.successMessage =
            null;
    }
}