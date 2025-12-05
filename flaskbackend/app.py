import os
import io
import base64
import json
from flask import Flask, request, jsonify, send_from_directory
from PIL import Image, ExifTags
from PIL import ImageOps
import tensorflow as tf
import numpy as np
from tensorflow.keras.applications import InceptionV3
from tensorflow.keras.models import load_model
from tensorflow.keras.applications.inception_v3 import preprocess_input  # Still imported if needed elsewhere
from dotenv import load_dotenv
import google.generativeai as genai
from werkzeug.utils import secure_filename
import gdown

# Suppress TensorFlow INFO and WARNING messages
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

# Load environment variables
load_dotenv()
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if not GOOGLE_API_KEY:
    raise Exception("Google API key not found. Set it in your .env file")

genai.configure(api_key=GOOGLE_API_KEY)

if not os.path.exists('model.h5'):
    # Replace 'YOUR_FILE_ID' with the actual file ID from Google Drive.
    url = "https://drive.google.com/uc?export=download&id=1lVG07pJRAPCh2TDyzUmybPItyUZBRn70"
    gdown.download(url, 'model.h5', quiet=False)
# Load Inception V3 Model
IMG_SIZE = (299,299)
model = tf.keras.models.load_model('model.h5')

# Print model summary
print("Loaded Inception V3 Model:")
model.summary()

with open("trained_classes.json", "r") as f:
    class_labels = json.load(f)

print("Class order in trained_classes.json:", class_labels)

# Flask App Setup
app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

def get_unique_filename(directory, filename):
    """Generate a unique filename if a file with the same name exists."""
    base, ext = os.path.splitext(filename)  # Split name and extension
    counter = 1
    
    # Check if the file already exists
    while os.path.exists(os.path.join(directory, filename)):
        filename = f"{base}({counter}){ext}"
        counter += 1
    
    return filename

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/', methods=['GET'])
def home():
    return jsonify({"message": "Welcome to NutriSync Backend!"}), 200

# ----- New Helper Functions for Orientation Correction and Letterboxing -----
def correct_image_orientation(image):
    try:
        # Automatically rotate image according to EXIF orientation.
        image = ImageOps.exif_transpose(image)
    except Exception as e:
        print("Error correcting image orientation:", e)
    return image

def preprocess_image_with_padding(image, target_size):
    """
    Resize image while preserving aspect ratio by adding padding (letterboxing).
    Returns a square image of size target_size x target_size.
    """
    original_width, original_height = image.size
    scale = target_size / max(original_width, original_height)
    new_width = int(original_width * scale)
    new_height = int(original_height * scale)
    resized_image = image.resize((new_width, new_height))
    new_image = Image.new("RGB", (target_size, target_size))
    paste_x = (target_size - new_width) // 2
    paste_y = (target_size - new_height) // 2
    new_image.paste(resized_image, (paste_x, paste_y))
    return new_image
# ---------------------------------------------------------------------------

def predict_food_from_image(image):
    try:
        # Correct orientation.
        image = correct_image_orientation(image)
        # Resize with padding to preserve aspect ratio.
        img_processed = preprocess_image_with_padding(image, IMG_SIZE[0])
        img_array = np.array(img_processed)

        # Convert grayscale or RGBA to RGB.
        if len(img_array.shape) == 2:
            img_array = np.stack((img_array,) * 3, axis=-1)
        if img_array.shape[-1] == 4:
            img_array = img_array[..., :3]

        # Expand dimensions to match model input.
        img_array = np.expand_dims(img_array, axis=0)

        print("Processed Image Shape:", img_array.shape)

        # Make prediction.
        predictions = model.predict(img_array)

        if predictions is None or len(predictions) == 0 or len(predictions[0]) == 0:
            return "unknown", 0.0

        # Get highest probability class.
        predicted_index = np.argmax(predictions[0])
        confidence = float(predictions[0][predicted_index])

        # Ensure index is valid.
        if predicted_index >= len(class_labels):
            predicted_food = "unknown"
        else:
            predicted_food = class_labels[predicted_index]

        print(f"Predicted Food: {predicted_food}, Confidence: {confidence:.4f}")
        return predicted_food, confidence

    except Exception as e:
        print("Error in predict_food_from_image:", e)
        return "unknown", 0.0

def input_image_setup(uploaded_file):
    try:
        return [{
            "mime_type": "image/jpeg",
            "data": uploaded_file.read()
        }]
    except Exception as e:
        print("Error in input_image_setup:", e)
        return []

def get_gemini_response(food_item, image_data, prompt):
    try:
        model = genai.GenerativeModel("gemini-1.5-flash-latest")
        response = model.generate_content([food_item, image_data[0], prompt])
        return response.text
    except Exception as e:
        print("Error in get_gemini_response:", e)
        return f"Error retrieving nutritional details: {str(e)}"

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'image' not in request.files:
        return jsonify({"error": "No image uploaded"}), 400

    image = request.files['image']
    
    if image.filename == '':
        return jsonify({"error": "No selected file"}), 400
    
    if not allowed_file(image.filename):
        return jsonify({"error": "Invalid file format"}), 400

    try:
        # Extract user details from the form data (if provided)
        age = request.form.get('age', '')
        weight = request.form.get('weight', '')
        activity_level = request.form.get('activityLevel', '')
        health_conditions = request.form.get('healthConditions', '')
        additional_notes = request.form.get('additionalNotes', '')
        print(f"Received user details - Age: {age}, Weight: {weight}, Activity Level: {activity_level}, Health Conditions: {health_conditions}, Additional Notes: {additional_notes}")
        user_details = ""
        if any([age, weight, activity_level, health_conditions, additional_notes]):
            user_details = f" User details: Age: {age}, Weight: {weight}, Activity Level: {activity_level}, Health Conditions: {health_conditions}, Additional Notes: {additional_notes}."

        # Save image locally
        filename = secure_filename(image.filename)
        filename = get_unique_filename(app.config["UPLOAD_FOLDER"], filename)
        image_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)

        image.save(image_path)
        image_url = f"https://h0qrgv67-5000.inc1.devtunnels.ms/uploads/{filename}"

        # Open saved image for processing
        img_obj = Image.open(image_path).convert('RGB')
        predicted_food, confidence = predict_food_from_image(img_obj)
        confidence_threshold = 0.6
        confidence = float(confidence)
        
        # Reset file pointer for Gemini processing
        image.seek(0)
        image_data = input_image_setup(image)

        # Build prompt based on classifier confidence and include user details if available.
        if predicted_food == "unknown" or confidence < confidence_threshold:
            prompt = (
                "Analyze the nutritional content of food. "
                "Don't mention that it is impossible to predict without ingredients. "
                "Provide estimated values only. "
                "Give a short breakdown of Calories, Protein (g), Carbohydrates (g), Fats (g), Fiber (g), and Sugars (g) "
                "along with brief dietary recommendations according to user details from " + user_details + " in a very short and understandable format & suggest user if not suitable for his/her health condition. "
                "Do not use any bold formatting."
            )
        else:
            prompt = (
                f"Analyze the nutritional content of {predicted_food}."
                "Don't mention that it is impossible to predict without ingredients. "
                "Provide estimated values only. "
                "Give a short breakdown of Calories, Protein (g), Carbohydrates (g), Fats (g), Fiber (g), and Sugars (g) "
                "along with brief dietary recommendations according to user details from " + user_details + " in a very short and understandable format & suggest user if not suitable for his/her health condition. "
                "Do not use any bold formatting."
            )
        
        nutritional_response = get_gemini_response(predicted_food, image_data, prompt)
        
        return jsonify({
            "predicted_food": predicted_food,
            "confidence": confidence,
            "nutritional_info": nutritional_response,
            "image_url": image_url  # Add image URL to response
        }), 200

    except Exception as e:
        print("Error processing upload:", e)
        return jsonify({"error": str(e)}), 500
    

@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json(force=True)
    image_data = data.get('image', None)
    if (image_data is None):
        return jsonify({'error': 'No image provided'}), 400

    # Remove the data URL scheme if present.
    if "base64," in image_data:
        image_data = image_data.split("base64,")[1]

    try:
        # Decode the image data.
        img_bytes = base64.b64decode(image_data)
        image = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    except Exception as e:
        return jsonify({'error': 'Invalid image data', 'details': str(e)}), 400

    try:
        # Correct orientation and preserve aspect ratio.
        image = correct_image_orientation(image)
        image = preprocess_image_with_padding(image, IMG_SIZE[0])
        img_array = np.array(image)
        # Convert grayscale or RGBA to RGB if necessary.
        if len(img_array.shape) == 2:
            img_array = np.stack((img_array,) * 3, axis=-1)
        if img_array.shape[-1] == 4:
            img_array = img_array[..., :3]
        # Expand dimensions to match model input.
        img_array = np.expand_dims(img_array, axis=0)

        print("Processed Image Shape:", img_array.shape)
        # Run inference.
        predictions = model.predict(img_array)
        # Flatten the predictions list.
        pred_list = predictions[0].tolist()

        # Create a list of (label, confidence) pairs.
        pred_pairs = []
        for idx, conf in enumerate(pred_list):
            label = class_labels[idx] if idx < len(class_labels) else "unknown"
            pred_pairs.append({
                'predicted_class': label,
                'confidence': float(conf)
            })

        # Sort descending by confidence.
        pred_pairs.sort(key=lambda x: x['confidence'], reverse=True)
        # Take top prediction.
        top_prediction = pred_pairs[0] if pred_pairs else {}

        print("Top prediction:", top_prediction)
        return jsonify({
            'predictions': [top_prediction]
        })
    except Exception as e:
        print("Error in predict endpoint:", e)
        return jsonify({'predictions': []})

# Add endpoint to serve uploaded images
@app.route('/uploads/<filename>')
def serve_uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({"message": "pong"}), 200


if __name__ == '__main__':
    app.run(debug=True, host="0.0.0.0", port=5000)
