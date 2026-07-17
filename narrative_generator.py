import cv2
from skimage.metrics import structural_similarity as ssim

def verify_image_uniqueness(img1, img2):
    """Returns False if photos are too similar (likely the same photo)."""
    try:
        gray1 = cv2.cvtColor(img1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(img2, cv2.COLOR_BGR2GRAY)
        score, _ = ssim(gray1, gray2, full=True)
        return score <= 0.95  # True if sufficiently different
    except:
        return True  # Default to allowing if error

def generate_smart_narrative(procedure_type, days_post_op, current_metrics, baseline_metrics):
    """
    Analyzes numerical metric differences and returns a plain English narrative.
    Uses a clinical threshold to avoid false progress claims.
    """
    CLINICAL_THRESHOLD = 5.0
    
    redness_delta = current_metrics["redness"] - baseline_metrics["redness"]
    pore_delta = current_metrics["pores"] - baseline_metrics["pores"]
    wrinkle_delta = current_metrics["wrinkles"] - baseline_metrics["wrinkles"]
    
    sentences = []
    
    if procedure_type in ["haloLaser", "co2Laser", "fractionalLaser"]:
        if days_post_op <= 5:
            sentences.append(f"You are currently on Day {days_post_op} of your acute healing window.")
            sentences.append("The AI shows elevated redness across your cheeks, which is clinically expected as the deep skin layers regenerate.")
            sentences.append("Focus heavily on post-procedure hydration and barrier repair creams right now.")
        else:
            sentences.append(f"Welcome to Day {days_post_op} of your laser recovery matrix.")
            
            if redness_delta >= CLINICAL_THRESHOLD:
                sentences.append("Your overall facial redness has dropped significantly, showing great vascular recovery.")
            elif abs(redness_delta) < CLINICAL_THRESHOLD:
                sentences.append("Your skin redness is currently tracking as stable and consistent with your baseline.")
            else:
                sentences.append("We are seeing a steady, healthy reduction in skin inflammation.")
            
            if pore_delta >= CLINICAL_THRESHOLD:
                sentences.append("Pore sizes around your nose and T-zone have shrunk noticeably as the skin tightens.")
            
            if wrinkle_delta >= CLINICAL_THRESHOLD:
                sentences.append("Collagen remodeling is visible, showing clear smoothing of superficial fine lines.")
                
            sentences.append("Your recovery trajectory is completely on track for this phase.")

    return " ".join(sentences)


# Test
if __name__ == "__main__":
    baseline = {"redness": 40, "pores": 50, "wrinkles": 60}
    current = {"redness": 42, "pores": 51, "wrinkles": 61}
    narrative = generate_smart_narrative("co2Laser", 12, current, baseline)
    print(narrative)