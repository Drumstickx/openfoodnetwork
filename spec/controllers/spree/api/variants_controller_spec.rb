require 'spec_helper'

module Spree
  describe Spree::Api::VariantsController, type: :controller do
    render_views

    let(:supplier) { FactoryBot.create(:supplier_enterprise) }
    let!(:variant1) { FactoryBot.create(:variant) }
    let!(:variant2) { FactoryBot.create(:variant) }
    let!(:variant3) { FactoryBot.create(:variant) }
    let(:attributes) { [:id, :options_text, :price, :on_hand, :unit_value, :unit_description, :on_demand, :display_as, :display_name] }

    before do
      allow(controller).to receive(:spree_current_user) { current_api_user }
    end

    context "as a normal user" do
      sign_in_as_user!

      it "retrieves a list of variants with appropriate attributes" do
        spree_get :index, { :template => 'bulk_index', :format => :json }
        keys = json_response.first.keys.map{ |key| key.to_sym }
        expect(attributes.all?{ |attr| keys.include? attr }).to eq(true)
      end

      it "is denied access when trying to delete a variant" do
        product = create(:product)
        variant = product.master

        spree_delete :soft_delete, {variant_id: variant.to_param, product_id: product.to_param, format: :json}
        assert_unauthorized!
        expect { variant.reload }.not_to raise_error
        expect(variant.deleted_at).to be_nil
      end
    end

    context "as an enterprise user" do
      sign_in_as_enterprise_user! [:supplier]
      let(:supplier_other) { create(:supplier_enterprise) }
      let(:product) { create(:product, supplier: supplier) }
      let(:variant) { product.master }
      let(:product_other) { create(:product, supplier: supplier_other) }
      let(:variant_other) { product_other.master }

      it "soft deletes a variant" do
        spree_delete :soft_delete, {variant_id: variant.to_param, product_id: product.to_param, format: :json}
        expect(response.status).to eq(204)
        expect { variant.reload }.not_to raise_error
        expect(variant.deleted_at).to be_present
      end

      it "is denied access to soft deleting another enterprises' variant" do
        spree_delete :soft_delete, {variant_id: variant_other.to_param, product_id: product_other.to_param, format: :json}
        assert_unauthorized!
        expect { variant.reload }.not_to raise_error
        expect(variant.deleted_at).to be_nil
      end

      context 'when the variant is not the master' do
        before { variant.update_attribute(:is_master, false) }

        it 'refreshes the cache' do
          expect(OpenFoodNetwork::ProductsCache).to receive(:variant_destroyed).with(variant)
          spree_delete :soft_delete, variant_id: variant.id, product_id: variant.product.permalink, format: :json
        end
      end
    end

    context "as an administrator" do
      sign_in_as_admin!

      let(:product) { create(:product) }
      let(:variant) { product.master }

      it "soft deletes a variant" do
        spree_delete :soft_delete, {variant_id: variant.to_param, product_id: product.to_param, format: :json}
        expect(response.status).to eq(204)
        expect { variant.reload }.not_to raise_error
        expect(variant.deleted_at).not_to be_nil
      end

      it "doesn't delete the only variant of the product" do
        product = create(:product)
        variant = product.variants.first

        spree_delete :soft_delete, {variant_id: variant.to_param, product_id: product.to_param, format: :json}

        expect(variant.reload).to_not be_deleted
        expect(assigns(:variant).errors[:product]).to include "must have at least one variant"
      end

      context 'when the variant is not the master' do
        before { variant.update_attribute(:is_master, false) }

        it 'refreshes the cache' do
          expect(OpenFoodNetwork::ProductsCache).to receive(:variant_destroyed).with(variant)
          spree_delete :soft_delete, variant_id: variant.id, product_id: variant.product.permalink, format: :json
        end
      end
    end
  end
end
