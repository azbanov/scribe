defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "jobtitle",
          label: "Job Title",
          current_value: nil,
          new_value: "Engineer",
          context: "Works as engineer",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        jobtitle: "Engineer",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since jobtitle already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end

    test "sets apply to true for all returned suggestions" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert Enum.all?(result, fn s -> s.apply == true end)
    end

    test "sets has_change to true for all returned suggestions" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert Enum.all?(result, fn s -> s.has_change == true end)
    end

    test "populates current_value from contact data" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-9999",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: "555-1234"}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).current_value == "555-1234"
    end

    test "handles nil contact field values" do
      suggestions = [
        %{
          field: "department",
          label: "Department",
          current_value: nil,
          new_value: "Engineering",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", department: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 1
      assert hd(result).current_value == nil
      assert hd(result).new_value == "Engineering"
    end

    test "handles Salesforce-specific fields" do
      suggestions = [
        %{
          field: "homephone",
          label: "Home Phone",
          current_value: nil,
          new_value: "555-HOME",
          context: "test",
          apply: false,
          has_change: true
        },
        %{
          field: "department",
          label: "Department",
          current_value: nil,
          new_value: "Sales",
          context: "test",
          apply: false,
          has_change: true
        },
        %{
          field: "otherphone",
          label: "Other Phone",
          current_value: nil,
          new_value: "555-OTHER",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        homephone: nil,
        department: "Sales",
        otherphone: "555-OTHER"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only homephone should remain (department and otherphone match)
      assert length(result) == 1
      assert hd(result).field == "homephone"
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end

    test "jobtitle maps to 'Job Title'" do
      suggestions = [
        %{
          field: "jobtitle",
          label: "Job Title",
          current_value: nil,
          new_value: "CTO",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", jobtitle: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Job Title"
    end

    test "mobilephone maps to 'Mobile Phone'" do
      suggestions = [
        %{
          field: "mobilephone",
          label: "Mobile Phone",
          current_value: nil,
          new_value: "555-MOBILE",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", mobilephone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Mobile Phone"
    end
  end
end
