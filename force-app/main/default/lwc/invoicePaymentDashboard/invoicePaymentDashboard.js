import { LightningElement, wire, track, api } from 'lwc';
import getBillingAccounts from '@salesforce/apex/ChronarPayController.getBillingAccounts';
import getInvoiceDashboardData from '@salesforce/apex/ChronarPayController.getInvoiceDashboardData';
import createPaymentRecord from '@salesforce/apex/ChronarPayController.createPaymentRecord';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class InvoicePaymentDashboard extends LightningElement {
    @api paymentGatewayId = '';

    // Dropdown options for accounts
    @track accountOptions = [];
    selectedAccountId = '';
    
    // Filters and statistics
    selectedFilter = 'All';
    @track dashboardStats = {
        balance: 0.00,
        totalAmountDue: 0.00,
        totalPastDue: 0.00,
        totalCredits: 0.00
    };
    @track invoices = [];
    
    // Loading states
    isLoading = true;
    isProcessing = false;
    
    // Modal & checkout form states
    isModalOpen = false;
    selectedInvoiceId = '';
    selectedInvoiceNumber = '';
    selectedInvoiceBalance = 0.00;
    
    // Payment inputs
    cardholderName = '';
    cardNumber = '';
    expiryDate = '';
    cvv = '';
    paymentAmount = 0.00;

    // Track wired accounts and invoices to support refreshing
    wiredAccountsResult;
    wiredInvoiceResult;

    // Fetch Accounts
    @wire(getBillingAccounts)
    wiredAccounts(result) {
        this.wiredAccountsResult = result;
        const { data, error } = result;
        if (data) {
            this.accountOptions = data.map(acc => {
                return { label: acc.Name, value: acc.Id };
            });
            if (data.length > 0) {
                this.selectedAccountId = data[0].Id;
            }
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to retrieve accounts: ' + error.body.message, 'error');
            this.isLoading = false;
        }
    }

    // Fetch Invoices and Dashboard details based on Account & Filter
    @wire(getInvoiceDashboardData, { accountId: '$selectedAccountId', statusFilter: '$selectedFilter' })
    wiredInvoices(result) {
        this.wiredInvoiceResult = result;
        const { data, error } = result;
        this.isLoading = true;
        if (data) {
            // Process statistics
            this.dashboardStats = {
                balance: data.balance || 0.00,
                totalAmountDue: data.totalAmountDue || 0.00,
                totalPastDue: data.totalPastDue || 0.00,
                totalCredits: data.totalCredits || 0.00
            };
            
            // Format and display invoices
            if (data.invoices) {
                this.invoices = data.invoices.map(inv => {
                    const statusClass = 'badge ' + inv.Status.toLowerCase().replace(' ', '-');
                    const isPaid = inv.Status === 'Paid';
                    return {
                        ...inv,
                        statusClass,
                        isPaid
                    };
                });
            } else {
                this.invoices = [];
            }
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to load invoice dashboard data: ' + error.body.message, 'error');
            this.isLoading = false;
        }
    }

    // Computed properties for UI elements
    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }

    get invoicesCount() {
        return this.invoices ? this.invoices.length : 0;
    }

    // Dynamic classes for filter buttons
    get filterBtnAllClass() {
        return 'filter-btn' + (this.selectedFilter === 'All' ? ' active' : '');
    }

    get filterBtnOpenClass() {
        return 'filter-btn' + (this.selectedFilter === 'Open' ? ' active' : '');
    }

    get filterBtnPastDueClass() {
        return 'filter-btn' + (this.selectedFilter === 'Past Due' ? ' active' : '');
    }

    get filterBtnPaidClass() {
        return 'filter-btn' + (this.selectedFilter === 'Paid' ? ' active' : '');
    }

    // Event Handlers
    handleAccountChange(event) {
        this.selectedAccountId = event.detail.value;
    }

    handleFilterClick(event) {
        this.selectedFilter = event.target.dataset.filter;
    }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this.wiredAccountsResult),
            refreshApex(this.wiredInvoiceResult)
        ]).finally(() => {
            this.isLoading = false;
        });
    }

    // Modal Controls
    openPaymentModal(event) {
        this.selectedInvoiceId = event.target.dataset.id;
        this.selectedInvoiceNumber = event.target.dataset.number;
        this.selectedInvoiceBalance = parseFloat(event.target.dataset.balance);
        this.paymentAmount = this.selectedInvoiceBalance;
        
        // Reset checkout form fields
        this.cardholderName = '';
        this.cardNumber = '';
        this.expiryDate = '';
        this.cvv = '';
        
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    // Form inputs handling & formatting
    handleCardholderInput(event) {
        this.cardholderName = event.target.value;
    }

    handleCardNumberInput(event) {
        // Strip non-digits and add spaces every 4 characters
        let value = event.target.value.replace(/\D/g, '');
        let formatted = '';
        for (let i = 0; i < value.length; i++) {
            if (i > 0 && i % 4 === 0) {
                formatted += ' ';
            }
            formatted += value[i];
        }
        this.cardNumber = formatted;
        event.target.value = formatted;
    }

    handleExpiryInput(event) {
        // Strip non-digits and add slash in MM/YY format
        let value = event.target.value.replace(/\D/g, '');
        if (value.length > 2) {
            value = value.substring(0, 2) + '/' + value.substring(2, 4);
        }
        this.expiryDate = value;
        event.target.value = value;
    }

    handleCVVInput(event) {
        // Only allow up to 4 digits
        this.cvv = event.target.value.replace(/\D/g, '').substring(0, 4);
        event.target.value = this.cvv;
    }

    handleAmountInput(event) {
        this.paymentAmount = parseFloat(event.target.value);
    }

    // Submit Salesforce Payment
    handlePaymentSubmit(event) {
        event.preventDefault();
        
        if (!this.paymentAmount || this.paymentAmount <= 0) {
            this.showToast('Error', 'Please enter a valid payment amount.', 'error');
            return;
        }

        if (this.paymentAmount > this.selectedInvoiceBalance) {
            this.showToast('Error', 'Payment amount cannot exceed the invoice balance.', 'error');
            return;
        }

        this.isProcessing = true;

        const expiryParts = (this.expiryDate || '').split('/');
        const expiryMonth = expiryParts[0] ? expiryParts[0].trim() : '';
        const expiryYear = expiryParts[1] ? '20' + expiryParts[1].trim() : '';

        // Call Apex to process the payment through Salesforce Payments
        createPaymentRecord({
            invoiceId: this.selectedInvoiceId,
            amount: this.paymentAmount,
            paymentGatewayId: this.paymentGatewayId,
            cardholderName: this.cardholderName,
            cardNumber: this.cardNumber.replace(/\s/g, ''),
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            cvv: this.cvv
        })
        .then((result) => {
            this.showToast(
                'Success', 
                `Salesforce Payment completed successfully. Payment ID: ${result}`, 
                'success'
            );
            this.closeModal();
            // Refresh wire to update dashboard values and invoice list
            return refreshApex(this.wiredInvoiceResult);
        })
        .catch(error => {
            this.showToast('Error processing payment', error.body.message, 'error');
        })
        .finally(() => {
            this.isProcessing = false;
        });
    }

    // Toast Utility
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}