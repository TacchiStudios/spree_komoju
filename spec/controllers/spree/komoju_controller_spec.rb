require "spec_helper"

describe Spree::KomojuController, type: :controller do
  routes { Spree::Core::Engine.routes }

  describe "#callback" do
    context 'when callback is verified' do
      before do
        allow(OpenSSL::HMAC).to receive(:hexdigest) { "signature" }
        request.env["HTTP_X_KOMOJU_SIGNATURE"] = "signature"
      end

      context 'when type is ping' do
        it 'returns a successful response' do
          post :callback, {type: "ping"}

          expect(response.status).to eq(200)
        end
      end

      context 'when type is payment.refunded' do
        let(:order) { create :order, number: "SPREEORDER" }
        let(:payment) { create :payment, order: order, state: state, number: "PAYMENTID" }
        let(:refund_description) { "Test refund" }
        let(:refund_params) do
          {
            "type" => "payment.refunded",
            "data" => {
              "external_order_num" => "SPREEORDER-PAYMENTID",
              "refunds" => [{
                "description": refund_description
              }]
            }
          }
        end

        context "when payment exists" do
          context 'when payment has not been completed yet' do
            let(:state) { "pending" }

            it 'does nothing' do
              expect { post :callback, refund_params }.not_to change {payment.refunds.count}
            end
          end

          context 'when payment has already been completed' do
            let(:state) { "completed" }

            it 'does nothing' do
              expect { post :callback, refund_params }.to change {payment.refunds.count}.from(0).to(1)
              refund = payment.refunds.first
              expect(refund.amount).to eq payment.amount
              expect(refund.reason.name).to eq "Test refund"
            end
          end

        end
      end

      context 'when type is payment.captured' do
        let(:payment) { double Spree::Payment, complete!: true, completed?: completed }
        let(:capture_params) do
          {
            "type" => "payment.captured",
            "data" => {
              "external_order_num" => "SPREEORDER-PAYMENTID",
            }
          }
        end

        context 'when payment exists' do
          context 'when payment has already been completed' do
            let(:completed) { true }

            it 'does nothing' do
              allow_any_instance_of(Spree::KomojuController).to receive(:payment) { payment }

              post :callback, capture_params

              expect(payment).to_not have_received(:complete!)
            end
          end

          context 'when payment has not been completed yet' do
            let(:completed) { false }

            it 'marks a payment as complete' do
              allow_any_instance_of(Spree::KomojuController).to receive(:payment) { payment }

              post :callback, capture_params

              expect(payment).to have_received(:complete!)
            end
          end
        end

        context 'when payment doesnt exist' do
          it 'raises an activerecord error' do
            expect {
              post :callback, capture_params
            }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end

      context 'when type is not recognized' do
        it 'returns an 200 status code' do
          post :callback, {type: "bad_type"}
          expect(response.status).to eq(200)
        end
      end
    end

    context 'when callback is unverified' do
      it 'returns head unauthorized' do
        post :callback
        expect(response.status).to eq(401)
      end
    end
  end
end
